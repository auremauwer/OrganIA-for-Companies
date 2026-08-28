#!/usr/bin/env bash
# Inventario de todo lo que OrganIA tiene desplegado en AWS.
#
#   ./infra/inventario.sh            # recursos y gasto del mes
#   ./infra/inventario.sh --costos   # ademas, desglose por servicio
#
# Se apoya en la etiqueta Project=organia, que es una de las dos
# etiquetas activadas para asignacion de costos en esta cuenta.
set -euo pipefail

PERFIL="${PERFIL:-openbank}"
REGION="${REGION:-us-east-1}"
PROYECTO="${PROYECTO:-organia}"

echo "Inventario de '$PROYECTO' en la cuenta $(aws sts get-caller-identity \
  --profile "$PERFIL" --query Account --output text)"
echo

# ---------------------------------------------------------------------
# 1. Recursos etiquetados
# ---------------------------------------------------------------------
echo "RECURSOS ETIQUETADOS (Project=$PROYECTO)"
aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Project,Values=$PROYECTO" \
  --profile "$PERFIL" --region "$REGION" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null \
  | tr '\t' '\n' | sed 's/^/  /' | sort || echo "  (ninguno)"
echo

# ---------------------------------------------------------------------
# 2. Recursos que AWS no permite etiquetar. Se rastrean por su stack:
#    CloudFormation es la fuente de verdad de que existen.
# ---------------------------------------------------------------------
echo "RECURSOS SIN SOPORTE DE ETIQUETAS (se listan por stack)"
for STACK in "$PROYECTO" "$PROYECTO-cognito"; do
  if aws cloudformation describe-stacks --stack-name "$STACK" \
       --profile "$PERFIL" --region "$REGION" >/dev/null 2>&1; then
    echo "  --- $STACK ---"
    aws cloudformation list-stack-resources --stack-name "$STACK" \
      --profile "$PERFIL" --region "$REGION" \
      --query 'StackResourceSummaries[?ResourceType==`AWS::CloudFront::OriginAccessControl`
               || ResourceType==`AWS::CloudFront::ResponseHeadersPolicy`
               || ResourceType==`AWS::S3::BucketPolicy`
               || ResourceType==`AWS::Cognito::UserPoolClient`
               || ResourceType==`AWS::Cognito::UserPoolDomain`
               || ResourceType==`AWS::Budgets::Budget`].[ResourceType,PhysicalResourceId]' \
      --output text 2>/dev/null | sed 's/^/    /'
  else
    echo "  --- $STACK: no existe ---"
  fi
done
echo

# ---------------------------------------------------------------------
# 3. Gasto del mes en curso
# ---------------------------------------------------------------------
INICIO="$(date -u +%Y-%m-01)"
FIN="$(date -u +%Y-%m-%d)"

if [[ "$INICIO" == "$FIN" ]]; then
  echo "GASTO DEL MES: es dia 1, aun no hay datos consolidados."
  exit 0
fi

echo "GASTO DEL MES ($INICIO a $FIN)"
if [[ "${1:-}" == "--costos" ]]; then
  aws ce get-cost-and-usage \
    --time-period "Start=$INICIO,End=$FIN" \
    --granularity MONTHLY --metrics UnblendedCost \
    --filter "{\"Tags\":{\"Key\":\"Project\",\"Values\":[\"$PROYECTO\"]}}" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --profile "$PERFIL" --region "$REGION" \
    --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
    --output text 2>/dev/null | sed 's/^/  /' || echo "  (sin datos)"
else
  aws ce get-cost-and-usage \
    --time-period "Start=$INICIO,End=$FIN" \
    --granularity MONTHLY --metrics UnblendedCost \
    --filter "{\"Tags\":{\"Key\":\"Project\",\"Values\":[\"$PROYECTO\"]}}" \
    --profile "$PERFIL" --region "$REGION" \
    --query 'ResultsByTime[0].Total.UnblendedCost.[Amount,Unit]' \
    --output text 2>/dev/null | sed 's/^/  Total: /' || echo "  (sin datos)"
fi
