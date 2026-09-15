# Genera dos .xlsx de prueba para OrganIA.
# Un .xlsx es un ZIP con XML dentro, asi que se arma sin librerias externas.
import sys, zipfile, datetime

SALIDA = sys.argv[1]
NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'


def serie_excel(iso):
    """Fecha ISO -> numero de serie de Excel (dias desde 1899-12-30)."""
    d = datetime.date.fromisoformat(iso)
    return (d - datetime.date(1899, 12, 30)).days


def col(n):
    s, n = '', n + 1
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def escribir_xlsx(ruta, filas):
    textos, idx = [], {}

    def sid(v):
        if v not in idx:
            idx[v] = len(textos)
            textos.append(v)
        return idx[v]

    filas_xml = []
    for r, fila in enumerate(filas, start=1):
        celdas = []
        for c, v in enumerate(fila):
            if v == '' or v is None:
                continue
            ref = f'{col(c)}{r}'
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                celdas.append(f'<c r="{ref}"><v>{v}</v></c>')
            else:
                celdas.append(f'<c r="{ref}" t="s"><v>{sid(str(v))}</v></c>')
        filas_xml.append(f'<row r="{r}">{"".join(celdas)}</row>')

    esc = lambda s: (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'))

    with zipfile.ZipFile(ruta, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml',
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
            '</Types>')
        z.writestr('_rels/.rels',
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>')
        z.writestr('xl/workbook.xml',
            f'<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="{NS}" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Plantilla" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels',
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            '</Relationships>')
        z.writestr('xl/sharedStrings.xml',
            f'<?xml version="1.0" encoding="UTF-8"?><sst xmlns="{NS}" '
            f'count="{len(textos)}" uniqueCount="{len(textos)}">'
            + ''.join(f'<si><t xml:space="preserve">{esc(t)}</t></si>' for t in textos) + '</sst>')
        z.writestr('xl/worksheets/sheet1.xml',
            f'<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="{NS}">'
            f'<sheetData>{"".join(filas_xml)}</sheetData></worksheet>')


# ---------------------------------------------------------------------
#  Personal de "Marea Logistica", empresa ficticia de prueba.
#  (jefe, puesto del jefe, nombre, apellido, puesto, area, ingreso,
#   resumen, distintivo, tipo, periodo, motivo, otorgado por,
#   reconocimientos, foto, vacante, color)
# ---------------------------------------------------------------------
P = [
 ('', '', 'Elena', 'Ferrer', 'Directora General', 'Dirección General', '2016-03-07',
  'Encabeza la compañía y responde ante el consejo.', '', '', '', '', '', '',
  'photos/elena-ferrer.jpg', 'No', '#111113'),

 ('Elena Ferrer', 'Directora General', 'Tomás', 'Vidal', 'Asistente de Dirección',
  'Dirección General', '2021-01-18', 'Coordina la agenda y los acuerdos del comité.',
  '', '', '', '', '', '', '', 'No', ''),

 # --- Tecnología -----------------------------------------------------
 ('Elena Ferrer', 'Directora General', 'Ricardo', 'Salas', 'Director de Tecnología',
  'Tecnología', '2017-09-04', 'Define la arquitectura y dirige a ingeniería.',
  '', '', '', '', '', '', '', 'No', '#e21c1c'),
 ('Ricardo Salas', 'Director de Tecnología', 'Paula', 'Mena', 'Jefa de Ingeniería',
  '', '2019-05-13', 'Dirige los equipos de desarrollo de producto.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Paula Mena', 'Jefa de Ingeniería', 'Carlos', 'Ruiz', 'Desarrollador Senior',
  '', '2020-11-09', 'Desarrolla y mantiene los servicios del producto.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Paula Mena', 'Jefa de Ingeniería', 'Nadia', 'Okonkwo', 'Desarrolladora',
  '', '23/02/2022', 'Trabaja en la interfaz del portal de clientes.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Paula Mena', 'Jefa de Ingeniería', 'Iván', 'Prats', 'Becario de Ingeniería',
  '', '2025-08-01', '', '', '', '', '', '', '', '', 'No', ''),
 ('Ricardo Salas', 'Director de Tecnología', 'Sofía', 'Iglesias', 'Jefa de Datos',
  '', '2018-06-25', 'Encabeza analítica y los modelos de predicción de demanda.',
  'AI Champion', 'ai', '', '', 'Elena Ferrer',
  'Ricardo Salas: sacó adelante el modelo de rutas en tiempo récord', '', 'No', ''),
 ('Sofía Iglesias', 'Jefa de Datos', 'Bruno', 'Tapia', 'Ingeniero de Datos',
  '', '2023-04-17', 'Mantiene las canalizaciones de datos.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Sofía Iglesias', 'Jefa de Datos', '', '', 'Científico de Datos',
  '', '', 'Posición abierta: modelos de predicción de demanda.',
  '', '', '', '', '', '', '', 'Sí', ''),

 # --- Finanzas -------------------------------------------------------
 ('Elena Ferrer', 'Directora General', 'Marcos', 'Bianchi', 'Director de Finanzas',
  'Finanzas', '2017-02-20', 'Responsable de finanzas, tesorería y control.',
  '', '', '', '', '', '', '', 'No', '#17be79'),
 ('Marcos Bianchi', 'Director de Finanzas', 'Andrea', 'Lima', 'Contralora',
  '', '2019-10-07', 'Supervisa la contabilidad y el cierre mensual.',
  '', '', '', '', '', '', '', 'No', ''),
 # Homónimo del desarrollador: se distingue por el puesto de su jefa
 ('Andrea Lima', 'Contralora', 'Carlos', 'Ruiz', 'Analista Contable',
  '', '2024-01-15', 'Concilia cuentas y apoya el cierre mensual.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Marcos Bianchi', 'Director de Finanzas', 'Hugo', 'Pereda', 'Jefe de Tesorería',
  '', '2021-07-05', 'Administra el flujo de efectivo y la relación bancaria.',
  '', '', '', '', '', '', '', 'No', ''),

 # --- Personas -------------------------------------------------------
 ('Elena Ferrer', 'Directora General', 'Lucía', 'Ramos', 'Directora de Personas',
  'Personas', '2018-11-12', 'Encabeza atracción de talento, cultura y compensaciones.',
  '', '', '', '', '', '', '', 'No', '#d4a017'),
 ('Lucía Ramos', 'Directora de Personas', 'Diego', 'Arce', 'Jefe de Reclutamiento',
  '', '2022-03-28', 'Lidera la atracción de talento para toda la compañía.',
  'Colaborador Destacado', 'destacado', 'Agosto 2026',
  'Cubrió doce posiciones críticas en un trimestre.', 'Lucía Ramos',
  'Valeria Cano: siempre disponible para revisar candidatos | Elena Ferrer: gran trabajo este trimestre',
  '', 'No', ''),
 ('Diego Arce', 'Jefe de Reclutamiento', 'Valeria', 'Cano', 'Reclutadora',
  '', '2024-09-02', 'Reclutamiento para las áreas de operaciones y comercial.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Lucía Ramos', 'Directora de Personas', '', '', 'Especialista en Compensaciones',
  '', '', 'Posición abierta.', '', '', '', '', '', '', '', 'Sí', ''),

 # --- Operaciones ----------------------------------------------------
 ('Elena Ferrer', 'Directora General', 'Javier', 'Ocampo', 'Director de Operaciones',
  'Operaciones', '2016-08-22', 'Responsable de la operación logística nacional.',
  '', '', '', '', '', '', '', 'No', '#1cbbe2'),
 ('Javier Ocampo', 'Director de Operaciones', 'Carmen', 'Duarte', 'Jefa de Logística',
  '', '2019-02-11', 'Coordina la red de distribución y los centros de reparto.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Carmen Duarte', 'Jefa de Logística', 'Pablo', 'Ynzunza', 'Coordinador de Ruta',
  '', '2022-12-05', 'Planea las rutas de la zona norte.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Carmen Duarte', 'Jefa de Logística', 'Rosa', 'Mejía', 'Coordinadora de Ruta',
  '', '2023-06-19', 'Planea las rutas de la zona sur.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Javier Ocampo', 'Director de Operaciones', 'Esteban', 'Roldán', 'Jefe de Calidad',
  '', '2020-04-14', 'Asegura los estándares de servicio y atiende incidencias.',
  'AI Champion', 'ai', '', '', 'Javier Ocampo', '', '', 'No', ''),
 # Nombre de pila compuesto: prueba el corte nombre/apellido
 ('Esteban Roldán', 'Jefe de Calidad', 'Ana Belén', 'Soto', 'Analista de Calidad',
  '', '2024-05-06', 'Audita entregas y documenta hallazgos.',
  '', '', '', '', '', '', '', 'No', ''),

 # --- Comercial ------------------------------------------------------
 ('Elena Ferrer', 'Directora General', 'Teresa', 'Aguilar', 'Directora Comercial',
  'Comercial', '2018-01-29', 'Encabeza ventas, mercadotecnia y grandes cuentas.',
  '', '', '', '', '', '', '', 'No', '#aa1ce2'),
 ('Teresa Aguilar', 'Directora Comercial', 'Óscar', 'Ibarra', 'Jefe de Ventas',
  '', '2020-09-21', 'Dirige al equipo de ventas y las cuentas clave.',
  'Colaborador Destacado', 'destacado', 'Julio 2026',
  'Cerró el contrato más grande del año.', 'Teresa Aguilar', '', '', 'No', ''),
 ('Óscar Ibarra', 'Jefe de Ventas', 'Martín', 'Quiroga', 'Ejecutivo de Cuenta',
  '', '2023-02-13', 'Atiende cuentas del sector retail.',
  '', '', '', '', '', '', '', 'No', ''),
 ('Óscar Ibarra', 'Jefe de Ventas', 'Silvia', 'Navarro', 'Ejecutiva de Cuenta',
  '', '2025-01-20', 'Atiende cuentas del sector industrial.',
  '', '', '', '', '', '', '', 'No', ''),
]

# ---- Archivo 1: solo las 6 columnas que ya tiene su Excel ----
minimo = [['', 'Manager', 'Manager Position', 'Person-First Name',
           'Person-LastName', 'Role- Job Title']]
for i, p in enumerate(P, 1):
    if p[15] == 'Sí':
        continue                      # sin columna Vacant no tienen sentido
    minimo.append([i, p[0], p[1], p[2], p[3], p[4]])
escribir_xlsx(f'{SALIDA}/prueba-minima.xlsx', minimo)

# ---- Archivo 2: todas las columnas ----
completo = [['', 'Manager', 'Manager Position', 'Person-First Name',
             'Person-LastName', 'Role- Job Title', 'Department', 'Start Date',
             'Summary', 'Badge', 'Badge Type', 'Badge Period', 'Badge Reason',
             'Badge Granted By', 'Recognitions', 'Photo', 'Vacant', 'Accent']]
for i, p in enumerate(P, 1):
    fecha = p[6]
    # La directora general lleva la fecha como numero de serie de Excel,
    # para comprobar que tambien se interpreta bien.
    if i == 1 and fecha:
        fecha = serie_excel(fecha)
    completo.append([i, p[0], p[1], p[2], p[3], p[4], p[5], fecha,
                     p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16]])
escribir_xlsx(f'{SALIDA}/prueba-completa.xlsx', completo)

print(f'  prueba-minima.xlsx    {len(minimo) - 1} personas, 6 columnas')
print(f'  prueba-completa.xlsx  {len(completo) - 1} personas, 18 columnas')
