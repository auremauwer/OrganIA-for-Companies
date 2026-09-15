// Genera organia-datos.csv reutilizando el codigo real de index.html,
// para que el archivo publicado sea identico al que exporta la app.
const fs = require('fs');
const ruta = process.argv[2];
const html = fs.readFileSync(ruta + '/index.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function sacarFuncion(nombre) {
  const i = script.indexOf('function ' + nombre + '(');
  if (i < 0) throw new Error('no encontre la funcion ' + nombre);
  let prof = 0;
  for (let k = script.indexOf('{', i); k < script.length; k++) {
    if (script[k] === '{') prof++;
    else if (script[k] === '}' && --prof === 0) return script.slice(i, k + 1);
  }
}

function sacarLinea(decl) {
  const i = script.indexOf(decl);
  if (i < 0) throw new Error('no encontre ' + decl);
  return script.slice(i, script.indexOf('\n', i) + 1);
}

// ORG_DATA completo, contando llaves desde su apertura
const iData = script.indexOf('let ORG_DATA = {');
let prof = 0, fin = 0;
for (let k = script.indexOf('{', iData); k < script.length; k++) {
  if (script[k] === '{') prof++;
  else if (script[k] === '}' && --prof === 0) { fin = k + 1; break; }
}

const piezas = [
  script.slice(iData, fin),
  sacarFuncion('assignKeys'),
  sacarFuncion('keyOf'),
  sacarFuncion('inheritAccents'),
  sacarFuncion('countEmployees'),
  sacarFuncion('parseStartDate'),
  sacarFuncion('tenureText'),
  sacarFuncion('slugFoto'),
  sacarLinea('const _rutasFoto = new Map();'),
  sacarFuncion('rutaFotoDe'),
  sacarFuncion('flattenOrgForExport'),
  sacarFuncion('csvCell'),
];

const HEADERS = ['', 'Manager', 'Manager Position', 'Person-First Name',
  'Person-LastName', 'Role- Job Title', 'Department', 'Start Date',
  'Summary', 'Badge', 'Badge Type', 'Badge Period', 'Badge Reason',
  'Badge Granted By', 'Recognitions', 'Photo', 'Vacant', 'Accent',
  'Nivel', 'Antigüedad', 'Reportes directos', 'Total a cargo'];

const cuerpo = piezas.join('\n\n') + `
  assignKeys(ORG_DATA, new Map());
  inheritAccents(ORG_DATA, null, null, 0);
  const filas = flattenOrgForExport(ORG_DATA);
  return [HEADERS, ...filas].map(f => f.map(csvCell).join(',')).join(SALTO);
`;

const csv = new Function('HEADERS', 'SALTO', cuerpo)(HEADERS, '\r\n');
fs.writeFileSync(ruta + '/organia-datos.csv', '﻿' + csv, 'utf8');

console.log('  organia-datos.csv generado');
console.log('  filas de datos:', csv.split('\r\n').length - 1);
console.log('  bytes:', Buffer.byteLength('﻿' + csv));
