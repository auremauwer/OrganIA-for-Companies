'use strict';
/**
 * OrganIA - Guardia de acceso en el borde.
 *
 * Se ejecuta en CloudFront (viewer-request) ANTES de que se sirva nada desde
 * S3. Esto no es opcional: los 103 nombres viven dentro de index.html, asi que
 * una pantalla de login dentro de la pagina no protegeria nada. Para cuando el
 * navegador pudiera dibujarla, ya se habria descargado el archivo completo.
 *
 * Flujo:
 *   sin cookie          -> 302 a la pantalla de Cognito
 *   /_auth/callback     -> canjea el codigo por tokens y emite la cookie
 *   /_auth/logout       -> borra la cookie y cierra sesion en Cognito
 *   cookie valida       -> deja pasar la peticion a S3
 *
 * La sesion es una cookie propia firmada con HMAC, no el JWT de Cognito.
 * Validar un JWT aqui obligaria a descargar y cachear las llaves publicas
 * dentro de la funcion; con HMAC la verificacion es local y sin red, que es
 * justo lo que conviene en algo que corre en cada peticion.
 *
 * Lambda@Edge no admite variables de entorno: la configuracion se sustituye
 * al empaquetar (ver construir.sh).
 */

const crypto = require('crypto');
const https = require('https');

const CFG = {
  dominioCognito: '__DOMINIO_COGNITO__',
  clienteId:      '__CLIENTE_ID__',
  clienteSecreto: '__CLIENTE_SECRETO__',
  dominioSitio:   '__DOMINIO_SITIO__',
  secretoSesion:  '__SECRETO_SESION__',
  horasSesion:    8,
};

const NOMBRE_COOKIE = 'organia_sesion';
const RUTA_CALLBACK = '/_auth/callback';
const RUTA_LOGOUT   = '/_auth/logout';

// ---------------------------------------------------------------------
// Cookie de sesion: <cuerpo en base64url>.<firma HMAC>
// ---------------------------------------------------------------------

function firmar(cuerpo) {
  return crypto.createHmac('sha256', CFG.secretoSesion)
    .update(cuerpo)
    .digest('base64url');
}

function crearCookie(correo) {
  const expira = Date.now() + CFG.horasSesion * 3600 * 1000;
  const cuerpo = Buffer.from(JSON.stringify({ correo, expira })).toString('base64url');
  return `${cuerpo}.${firmar(cuerpo)}`;
}

function leerCookie(valor) {
  if (!valor || typeof valor !== 'string') return null;
  const corte = valor.lastIndexOf('.');
  if (corte < 1) return null;

  const cuerpo = valor.slice(0, corte);
  const firma  = valor.slice(corte + 1);
  const esperada = firmar(cuerpo);

  // Comparacion en tiempo constante: evita filtrar la firma correcta
  // midiendo cuanto tarda en fallar.
  const a = Buffer.from(firma);
  const b = Buffer.from(esperada);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  try {
    const datos = JSON.parse(Buffer.from(cuerpo, 'base64url').toString('utf8'));
    if (!datos.expira || Date.now() > datos.expira) return null;
    return datos;
  } catch (e) {
    return null;
  }
}

function parsearCookies(encabezados) {
  const salida = {};
  const crudas = (encabezados && encabezados.cookie) || [];
  for (const linea of crudas) {
    for (const parte of String(linea.value).split(';')) {
      const i = parte.indexOf('=');
      if (i > 0) salida[parte.slice(0, i).trim()] = parte.slice(i + 1).trim();
    }
  }
  return salida;
}

// ---------------------------------------------------------------------
// Respuestas
// ---------------------------------------------------------------------

function redirigir(destino, cookie) {
  const respuesta = {
    status: '302',
    statusDescription: 'Found',
    headers: {
      location: [{ key: 'Location', value: destino }],
      'cache-control': [{ key: 'Cache-Control', value: 'no-store' }],
    },
  };
  if (cookie) respuesta.headers['set-cookie'] = [{ key: 'Set-Cookie', value: cookie }];
  return respuesta;
}

function irALogin() {
  const destino = `https://${CFG.dominioCognito}/oauth2/authorize`
    + `?client_id=${encodeURIComponent(CFG.clienteId)}`
    + `&response_type=code`
    + `&scope=${encodeURIComponent('openid email profile')}`
    + `&redirect_uri=${encodeURIComponent(`https://${CFG.dominioSitio}${RUTA_CALLBACK}`)}`;
  return redirigir(destino);
}

function error(mensaje) {
  return {
    status: '403',
    statusDescription: 'Forbidden',
    headers: {
      'content-type': [{ key: 'Content-Type', value: 'text/html; charset=utf-8' }],
      'cache-control': [{ key: 'Cache-Control', value: 'no-store' }],
    },
    body: `<!doctype html><meta charset="utf-8">`
        + `<title>Sin acceso</title>`
        + `<div style="font:16px/1.6 system-ui;max-width:34em;margin:15vh auto;padding:0 1.5em">`
        + `<h1 style="font-size:1.3em">No se pudo validar tu acceso</h1>`
        + `<p>${mensaje}</p>`
        + `<p><a href="https://${CFG.dominioSitio}/">Intentar de nuevo</a></p></div>`,
  };
}

// ---------------------------------------------------------------------
// Canje del codigo por tokens
// ---------------------------------------------------------------------

function pedirTokens(codigo) {
  return new Promise((resolve, reject) => {
    const cuerpo = new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: CFG.clienteId,
      code: codigo,
      redirect_uri: `https://${CFG.dominioSitio}${RUTA_CALLBACK}`,
    }).toString();

    const credenciales = Buffer
      .from(`${CFG.clienteId}:${CFG.clienteSecreto}`)
      .toString('base64');

    const peticion = https.request({
      hostname: CFG.dominioCognito,
      path: '/oauth2/token',
      method: 'POST',
      timeout: 3000,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(cuerpo),
        Authorization: `Basic ${credenciales}`,
      },
    }, (res) => {
      let datos = '';
      res.on('data', (t) => { datos += t; });
      res.on('end', () => {
        if (res.statusCode !== 200) {
          return reject(new Error(`Cognito respondio ${res.statusCode}`));
        }
        try { resolve(JSON.parse(datos)); }
        catch (e) { reject(new Error('Respuesta ilegible de Cognito')); }
      });
    });

    peticion.on('timeout', () => { peticion.destroy(new Error('Cognito no respondio a tiempo')); });
    peticion.on('error', reject);
    peticion.write(cuerpo);
    peticion.end();
  });
}

// Solo se lee el correo para mostrarlo/registrarlo. La confianza no viene de
// este token sino de que Cognito acaba de entregarlo por un canal autenticado.
function correoDelToken(idToken) {
  try {
    const carga = idToken.split('.')[1];
    const json = JSON.parse(Buffer.from(carga, 'base64').toString('utf8'));
    return json.email || json['cognito:username'] || 'desconocido';
  } catch (e) {
    return 'desconocido';
  }
}

// ---------------------------------------------------------------------

exports.handler = async (event) => {
  const peticion = event.Records[0].cf.request;
  const uri = peticion.uri;

  if (uri === RUTA_LOGOUT) {
    const salir = `https://${CFG.dominioCognito}/logout`
      + `?client_id=${encodeURIComponent(CFG.clienteId)}`
      + `&logout_uri=${encodeURIComponent(`https://${CFG.dominioSitio}/`)}`;
    return redirigir(salir, `${NOMBRE_COOKIE}=; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=0`);
  }

  if (uri === RUTA_CALLBACK) {
    const parametros = new URLSearchParams(peticion.querystring || '');
    const codigo = parametros.get('code');
    if (!codigo) return irALogin();

    try {
      const tokens = await pedirTokens(codigo);
      const correo = correoDelToken(tokens.id_token || '');
      const cookie = `${NOMBRE_COOKIE}=${crearCookie(correo)}`
        + `; Path=/; Secure; HttpOnly; SameSite=Lax`
        + `; Max-Age=${CFG.horasSesion * 3600}`;
      return redirigir(`https://${CFG.dominioSitio}/`, cookie);
    } catch (e) {
      return error('No se pudo completar el inicio de sesion. ' + e.message);
    }
  }

  const cookies = parsearCookies(peticion.headers);
  if (leerCookie(cookies[NOMBRE_COOKIE])) return peticion;   // pasa a S3

  return irALogin();
};
