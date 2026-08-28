# Infraestructura de OrganIA

OrganIA se sirve desde un bucket privado de S3 a través de CloudFront, con el
acceso cerrado por Cognito y validado en el borde antes de entregar nada.

Cuenta `237921649041`, región `us-east-1`, perfil `openbank`.

## Por qué la autenticación va en el borde

Los datos de las 103 personas viven **dentro** de `index.html`; la aplicación no
hace ninguna petición de red. Una pantalla de acceso dentro de la página no
protegería nada: para poder dibujarla, el navegador ya se habría descargado el
archivo con todos los nombres. Por eso la validación ocurre en CloudFront, en el
evento `viewer-request`, antes de mirar la caché y antes de tocar S3.

## Archivos

| Archivo | Qué hace |
|---|---|
| `organia.yaml` | Bucket, CloudFront, encabezados de seguridad, presupuesto y guardia de acceso |
| `organia-cognito.yaml` | Pool de usuarios con segundo factor TOTP obligatorio |
| `edge-auth/index.js` | Función que valida la sesión en el borde |
| `edge-auth/construir.sh` | Incrusta la configuración en la función y la empaqueta |
| `deploy.sh` | Sube el sitio al bucket e invalida la caché |
| `inventario.sh` | Lista todos los recursos y el gasto del mes |

## Creación desde cero

Son tres pasos y el orden importa: el cliente de Cognito necesita la URL de
retorno, que no existe hasta que CloudFront está creado.

```bash
# 1. Base. Sin autenticación todavía: Cognito aún no existe.
aws cloudformation deploy \
  --template-file infra/organia.yaml --stack-name organia \
  --parameter-overrides CorreoPresupuesto=TU@CORREO ConAutenticacion=no \
  --tags Project=organia Environment=prod Owner=aure \
  --profile openbank --region us-east-1

# 2. Identidad, apuntando al dominio que devolvió el paso 1.
DOMINIO=$(aws cloudformation describe-stacks --stack-name organia \
  --profile openbank --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='UrlSitio'].OutputValue" \
  --output text | sed 's|https://||')

aws cloudformation deploy \
  --template-file infra/organia-cognito.yaml --stack-name organia-cognito \
  --parameter-overrides DominioCloudFront=$DOMINIO \
  --tags Project=organia Environment=prod Owner=aure \
  --profile openbank --region us-east-1

# 3. Encender el guardia de acceso.
./infra/edge-auth/construir.sh

aws cloudformation package \
  --template-file infra/organia.yaml \
  --s3-bucket aws-sam-cli-managed-default-samclisourcebucket-iezryv38deze \
  --output-template-file infra/organia-empaquetado.yaml \
  --profile openbank --region us-east-1

aws cloudformation deploy \
  --template-file infra/organia-empaquetado.yaml --stack-name organia \
  --parameter-overrides CorreoPresupuesto=TU@CORREO ConAutenticacion=si \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Project=organia Environment=prod Owner=aure \
  --profile openbank --region us-east-1
```

## Publicar cambios del sitio

```bash
./infra/deploy.sh
```

## Dar de alta a una persona

No hay auto-registro: las altas las hace un administrador.

```bash
POOL=$(aws cloudformation describe-stacks --stack-name organia-cognito \
  --profile openbank --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='IdPool'].OutputValue" --output text)

aws cognito-idp admin-create-user \
  --user-pool-id "$POOL" \
  --username persona@empresa.com \
  --user-attributes Name=email,Value=persona@empresa.com Name=email_verified,Value=true \
  --desired-delivery-mediums EMAIL \
  --profile openbank --region us-east-1
```

Cognito envía una contraseña temporal. Al entrar por primera vez se pide
cambiarla y escanear un código QR con Microsoft Authenticator (o cualquier app
TOTP) para el segundo factor.

## Etiquetas

Todo recurso que las admita lleva `Project`, `Environment`, `Owner` y
`Componente`. Las dos primeras son las únicas activadas para asignación de
costos en esta cuenta, por eso las llaves van en inglés.

No admiten etiquetas, por limitación de AWS: Origin Access Control, política de
encabezados, política del bucket, cliente y dominio de Cognito, y el
presupuesto. `inventario.sh` los recupera leyéndolos del stack.

## El rol de la función de borde necesita permisos que el usuario no tiene

El usuario `openbank-ia-deploy` no puede administrar roles de IAM. Al intentar
crear el rol de la función de borde, AWS respondió:

```
User: arn:aws:iam::237921649041:user/openbank-ia-deploy is not authorized
to perform: iam:GetRole on resource: role organia-guardia-acceso
```

Se intentó rodearlo pasando el ARN de un rol ya existente, mediante el
parámetro `ArnRolGuardia`. **No funciona**: aunque así no haga falta crear el
rol, Lambda exige `iam:PassRole` para recibirlo, y también está denegado:

```
not authorized to perform: iam:PassRole on resource:
arn:aws:iam::237921649041:role/organia-guardia-acceso
```

Es decir, no hay forma de desplegar la función de borde con este credencial.
Requiere que alguien con permisos de IAM haga una de estas dos cosas.

### Opción A — adjuntar la política faltante al usuario de despliegue

`permisos-iam-faltantes.json` tiene la política mínima, acotada a roles
`organia-*`: no da permiso sobre ningún otro rol de la cuenta. Con ella
adjunta a `openbank-ia-deploy`, el despliegue funciona sin parámetros extra:

```bash
aws iam put-user-policy --user-name openbank-ia-deploy \
  --policy-name organia-guardia-acceso \
  --policy-document file://infra/permisos-iam-faltantes.json
```

Es lo más cómodo a futuro, pero amplía un credencial de servicio. Si la
política de la organización lo desaconseja, usar la opción B.

### Opción B — que un administrador despliegue el paso 3

El administrador crea el rol y ejecuta el despliegue con su propio perfil, una
sola vez. Después, `deploy.sh` para publicar cambios del sitio sigue
funcionando con el usuario restringido, porque solo toca S3 y CloudFront.

```bash
# El rol ya podría existir del intento fallido: verificar antes de crearlo.
aws iam get-role --role-name organia-guardia-acceso || \
aws iam create-role --role-name organia-guardia-acceso \
  --assume-role-policy-document file://infra/rol-guardia-confianza.json \
  --tags Key=Project,Value=organia Key=Environment,Value=prod Key=Owner,Value=aure

aws iam attach-role-policy --role-name organia-guardia-acceso \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

./infra/edge-auth/construir.sh

aws cloudformation package \
  --template-file infra/organia.yaml \
  --s3-bucket aws-sam-cli-managed-default-samclisourcebucket-iezryv38deze \
  --s3-prefix organia/edge-auth \
  --output-template-file infra/organia-empaquetado.yaml \
  --profile PERFIL_ADMIN --region us-east-1

aws cloudformation deploy \
  --template-file infra/organia-empaquetado.yaml --stack-name organia \
  --parameter-overrides CorreoPresupuesto=TU@CORREO ConAutenticacion=si \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Project=organia Environment=prod Owner=aure \
  --profile PERFIL_ADMIN --region us-east-1
```

### Rol huérfano

El primer intento alcanzó a crear `organia-guardia-acceso` antes de fallar, y
la reversión no pudo borrarlo. Existe en la cuenta pero ya no pertenece a
ningún stack. Sirve para la opción B; si se descarta esa ruta, conviene
borrarlo para no dejar basura.

## Cosas que conviene saber

**Lambda@Edge es lento.** Cada cambio tarda entre 5 y 15 minutos en replicarse.
Al eliminar el stack, las réplicas pueden bloquear el borrado varias horas: es
normal, hay que esperar.

**El secreto de sesión vive fuera de git.** `infra/.secreto-sesion` firma las
cookies. Si se pierde, se genera otro y todo el mundo vuelve a entrar; no es
catastrófico, pero no lo borres sin necesidad.

**El bucket es `Retain`.** Eliminar el stack no borra el bucket ni su contenido,
a propósito. Hay que vaciarlo y borrarlo a mano si de verdad se quiere ir.

**Cuando llegue el SSO corporativo**, se agrega el proveedor federado al mismo
pool y se añade a `SupportedIdentityProviders` del cliente. CloudFront, el
bucket y la función de borde no se tocan.
