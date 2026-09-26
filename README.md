FONASALUD - RESULTADO FINANCIERO POR ASEGURADO
==============================================

Base de datos analítica en Microsoft SQL Server para medir el resultado
financiero (ingresos - costos) que genera cada asegurado de un seguro de
salud público, por cobertura, segmento, entidad empleadora, canal y
período.

Caso académico. Todos los datos de ejemplo son ficticios.

Contenido:
  1. Archivos
  2. Cómo ejecutar
  3. Tablas y vistas
  4. Caso propuesto y cómo lo resuelve el modelo
  5. Cumplimiento de las reglas de negocio
  6. Cumplimiento de los requerimientos de análisis
  7. Lógica de las relaciones
  8. Decisiones de diseño
  9. Extensiones posibles


==========================================================================
1. ARCHIVOS
==========================================================================

Scripts SQL:
  - seguro_salud_publico_v2.sql
      Crea la base: tablas, restricciones, índices y vistas.
  - poblar_seguro_salud_publico.sql
      Carga datos ficticios consistentes y ejecuta reportes de validación.
  - migracion_v1_a_v2.sql
      Convierte una base v1 que ya tiene datos al modelo v2.
  - fonasalud_v2_import.sql
      Solo tablas y relaciones, para importar en herramientas de diagrama.

Diagramas:
  - modelo_conceptual_v2.png           Modelo entidad-relación (Chen)
  - modelo_fisico_v2.png               Modelo físico (estilo SQL Server)
  - modelo_fisico_v2_dbdesigner.png    Modelo físico (estilo dbdesigner)


==========================================================================
2. CÓMO EJECUTAR
==========================================================================

Requisito: SQL Server 2016 SP1 o superior.

1. Crear la base: ejecutar seguro_salud_publico_v2.sql.
   Crea la base seguro_salud_publico con 13 tablas y 3 vistas.

2. Cargar datos de ejemplo: ejecutar poblar_seguro_salud_publico.sql.
   - Borra los datos existentes y genera unos 2 000 asegurados,
     60 000 atenciones, 65 000 ingresos y 70 000 costos entre enero de
     2025 y agosto de 2026.
   - Es determinista: con la misma semilla (@Seed) salen los mismos datos.
   - Al final ejecuta validaciones de consistencia y reportes de ejemplo.

3. Solo si ya existe una base v1 con datos: en lugar de los pasos 1 y 2,
   ejecutar migracion_v1_a_v2.sql. Sacar antes un respaldo y ejecutar
   primero solo el PASO 0 (diagnóstico).

Parámetros principales del script de datos:
  @Seed               20260925      Semilla de los valores aleatorios
  @NumAsegurados      2000          Cantidad de asegurados
  @NumEntidades       40            Cantidad de entidades empleadoras
  @TargetOperaciones  60000         Atenciones aproximadas a generar
  @Desde              2025-01-01    Inicio de los movimientos
  @DatosHasta         2026-08-31    Fin de los movimientos
  @CalDesde           2025-01-01    Inicio del calendario (periodos)
  @CalHasta           2026-12-31    Fin del calendario (periodos)


==========================================================================
3. TABLAS Y VISTAS
==========================================================================

Tablas:
  segmentos
      Tipos de asegurado: titular activo, titular pensionista,
      derechohabiente, cesante.
  entidades_empleadoras
      Entidades del Estado que emplean a los titulares y pagan el aporte
      de entidad.
  asegurados
      Personas cubiertas, con su segmento y su entidad ACTUALES.
  asegurados_condicion_hist
      Tramos de fechas con el segmento y la entidad que tuvo cada asegurado.
  categorias_cobertura
      Básica, complementaria, especial.
  coberturas
      Planes de salud y su aporte referencial.
  afiliaciones
      Asegurado + cobertura + vigencia. Es el eje del modelo.
  canales
      Vías de atención: red propia, referencia, telemedicina, farmacia,
      domicilio.
  periodos
      Calendario diario (año, mes, día, trimestre, semestre).
  cargas
      Bitácora de cada carga de datos desde los sistemas fuente.
  operaciones
      Una fila por atención.
  ingresos
      Aportes, transferencias del Tesoro y recuperaciones por subrogación.
  costos
      Prestaciones, referencias, procesamiento de reembolsos y gastos
      administrativos.

Vistas:
  vw_resultado_financiero
      Ingresos, costos y resultado por asegurado y día, con el segmento y
      la entidad vigentes en esa fecha.
  vw_resultado_financiero_mensual
      Lo mismo, consolidado por mes.
  vw_resultado_por_segmento_mensual
      Asegurados, ingresos, costos y resultado por segmento y mes.


==========================================================================
4. CASO PROPUESTO Y CÓMO LO RESUELVE EL MODELO
==========================================================================

El texto de cada sección resume el caso original. Debajo, el bloque
"MODELO v2" indica qué se implementó y qué quedó fuera del alcance
acotado.

Alcance acotado del proyecto: el modelo se centra en el resultado
financiero por asegurado. Quedan fuera los topes de cobertura y su
consumo, las credenciales y sus movimientos, el detalle de las solicitudes
de reembolso, las características de las coberturas (topes, copagos,
carencia), la IPRESS específica de cada atención, la ubicación geográfica
y el vínculo familiar entre titular y derechohabientes.


4.1 CONTEXTO DEL NEGOCIO
------------------------

FONASALUD es un fondo público de aseguramiento en salud que brinda
cobertura médica a los trabajadores de una entidad del Estado y a sus
derechohabientes. Se financia con aportes de planilla, transferencias del
Tesoro Público y aportes de pensionistas.

La información está distribuida en diferentes sistemas: afiliaciones,
atenciones médicas en la red de IPRESS, solicitudes de reembolso, aportes
recibidos y pagos realizados a prestadores de salud.

La gerencia necesita responder, entre otras: ¿cuánto le cuesta cada
asegurado al fondo?, ¿qué asegurados son superavitarios y cuáles
deficitarios?, ¿qué coberturas generan mayor costo?, ¿qué segmento genera
mayores aportes?, ¿cuánto se paga por prestaciones a las IPRESS de la red?,
¿cuánto cuesta mantener determinadas coberturas?, ¿cómo evoluciona el
resultado de un asegurado en el tiempo?, ¿es sostenible el fondo por
segmento y por cobertura?

  MODELO v2
  - Es una base analítica: no registra operaciones en línea, recibe la
    información de los sistemas fuente mediante cargas periódicas (tabla
    cargas). Cada atención, pago o liquidación llega como una fila.
  - El pago a las IPRESS de la red se obtiene de los costos de tipo
    PRESTACION cuyas operaciones son del canal IPRESS_RED.


4.2 ASEGURADOS Y ENTIDADES EMPLEADORAS
--------------------------------------

Se registran titulares (activos o pensionistas) y derechohabientes,
afiliados a través de la entidad empleadora del titular.

Datos del asegurado: código único, tipo de asegurado, documento, nombres,
fecha de nacimiento, sexo, estado, fecha de alta, segmento, ubicación
geográfica, entidad empleadora (cuando corresponda) y canal principal.

Datos de la entidad empleadora: código, nombre, sector o dependencia,
fecha de registro y estado.

Un asegurado puede cambiar de segmento (por ejemplo, de activo a
pensionista).

  MODELO v2
  - Implementado: código, documento, nombres, fecha de nacimiento, sexo,
    estado, fecha de alta, segmento y entidad empleadora.
  - Tipo de asegurado: lo determina el segmento; no se guarda aparte para
    que no se contradigan.
  - Canal principal: no se guarda; se calcula como el canal con más
    operaciones del asegurado, así siempre está actualizado.
  - Ubicación geográfica: fuera del alcance.
  - Entidad: implementada con código, nombre, RUC, sector, fecha de
    registro y estado.
  - Cambio de segmento y de entidad: tabla asegurados_condicion_hist, con
    un tramo de fechas por cada condición.


4.3 COBERTURAS DE SALUD
-----------------------

Coberturas como: Básica de Salud, Complementaria Odontológica,
Complementaria Oncológica, Alto Costo, para Pensionistas y otras. Cada una
pertenece a una categoría (básica, complementaria, especial).

Datos: código, nombre, categoría, tipo, estado, fecha de vigencia, aporte
de referencia, moneda y características (topes, copagos, carencia).

  MODELO v2
  - Implementado: código, nombre, categoría, estado, fecha de vigencia,
    aporte referencial y moneda.
  - Tipo de cobertura: lo determina la categoría.
  - Características (topes, copagos, carencia): fuera del alcance.
  - Los datos de ejemplo cargan: plan básico, dental, visual, atención
    domiciliaria, oncología y alto costo. La "Cobertura para Pensionistas"
    se puede agregar como una fila más sin cambiar el modelo.


4.4 AFILIACIÓN A COBERTURAS
---------------------------

El fondo registra la relación entre un asegurado y cada cobertura que le
corresponde. Ejemplo: Carlos Ramos está afiliado a la Cobertura Básica y,
al pasar a pensionista, se afilia además a la Cobertura para Pensionistas.

Datos: asegurado, cobertura, fecha de afiliación, fecha de baja, estado,
canal de registro, dependencia relacionada y condiciones aplicadas
(aporte pactado, copago). Un asegurado puede reafiliarse a la misma
cobertura a lo largo del tiempo (reingresos).

  MODELO v2
  - Implementado: asegurado, cobertura, fecha de afiliación, fecha de baja
    y estado (vigente, suspendida, baja).
  - Reingresos: permitidos. La clave única es (asegurado, cobertura,
    fecha de afiliación), y un índice impide tener dos afiliaciones
    abiertas a la misma cobertura al mismo tiempo.
  - Canal de registro, dependencia y condiciones pactadas: fuera del
    alcance. El aporte se calcula con el aporte referencial de la
    cobertura.
  - La afiliación es el eje del modelo: operaciones, ingresos y costos se
    registran sobre ella.


4.5 TOPES DE COBERTURA Y CONSUMO
--------------------------------

Los asegurados tienen topes por norma, que pueden compartirse en el núcleo
familiar. Se requiere el consumo acumulado, el saldo disponible y su
histórico por fecha.

  MODELO v2
  - Fuera del alcance. Ver la sección 9 (extensiones posibles).


4.6 CREDENCIALES DEL ASEGURADO
------------------------------

Un asegurado puede tener credenciales físicas o virtuales con número,
titular, cobertura, emisión, vencimiento, estado y tope para cartas de
garantía. Las credenciales generan movimientos (atenciones, cartas de
garantía, anulaciones).

  MODELO v2
  - Fuera del alcance. Las cartas de garantía se registran como
    operaciones de tipo CARTA_GARANTIA, sin la credencial.


4.7 SOLICITUDES DE REEMBOLSO
----------------------------

Los asegurados solicitan el reembolso de gastos pagados fuera de la red.
Cada solicitud tiene cobertura, fecha, monto, moneda, plazo, estado,
resolución y saldo pendiente, y genera pagos con componentes (monto
reembolsado, descuentos, penalidades).

  MODELO v2
  - Parcial. La solicitud se registra como una operación de tipo
    SOLICITUD_REEMBOLSO (importe bruto = monto solicitado). Genera un costo
    PRESTACION (monto reembolsado) y un costo PROCESAMIENTO_REEMBOLSO.
  - El detalle de plazos, saldo pendiente, descuentos y penalidades queda
    fuera del alcance.


4.8 ATENCIONES Y TRANSACCIONES
------------------------------

Canales: IPRESS propias, IPRESS de terceros por convenio o referencia,
telemedicina, farmacia convenio y atención domiciliaria. Prestaciones:
consultas, procedimientos, exámenes, medicamentos, hospitalizaciones,
emergencias.

Datos de cada atención: asegurado, cobertura, fecha y hora, tipo de
prestación, canal / IPRESS, importe y estado.

  MODELO v2
  - Implementado en la tabla operaciones: afiliación (asegurado y
    cobertura), fecha, tipo, canal, importe bruto y estado (liquidada,
    observada, rechazada), más el código de origen y la carga.
  - Tipos cargados: atención médica, referencia, carta de garantía y
    solicitud de reembolso. Otros tipos (consulta, procedimiento,
    hospitalización, etc.) se pueden registrar en el mismo campo.
  - Hora: no se guarda; el calendario es diario.
  - IPRESS específica: fuera del alcance; se analiza por canal.


4.9 INGRESOS DEL FONDO
----------------------

Aportes: del titular activo por planilla, de la entidad empleadora,
transferencias del Tesoro y aporte del pensionista. Otros ingresos:
recuperación o subrogación frente a terceros, reintegros y otros. Se deben
poder relacionar con el asegurado y la cobertura.

  MODELO v2
  - Tipos implementados: APORTE_ENTIDAD, APORTE_TITULAR (titular activo o
    pensionista), TRANSFERENCIA_TESORO y RECUPERACION_SUBROGACION.
  - Todo ingreso se registra sobre una afiliación, por lo que siempre
    identifica al asegurado y la cobertura.
  - El aporte de entidad guarda qué entidad pagó.
  - Solo la recuperación por subrogación se relaciona con una operación.
  - Reintegros y otros conceptos: no tienen tipo propio; se agregan al
    CHECK de tipo_ingreso si se necesitan.
  - Nota sobre los datos de ejemplo: para los titulares activos solo se
    genera el aporte de entidad. El modelo admite también su aporte por
    planilla (APORTE_TITULAR).


4.10 COSTOS ASOCIADOS
---------------------

Costos por prestaciones a las IPRESS, referencias interinstitucionales,
procesamiento de reembolsos, canales de atención, administrativos y otros.
No todos se generan por una atención; algunos se distribuyen con criterios
del área financiera.

  MODELO v2
  - Tipos implementados: PRESTACION, REFERENCIA_INTERINSTITUCIONAL,
    PROCESAMIENTO_REEMBOLSO y ADMINISTRATIVO.
  - Todo costo se registra sobre una afiliación. Los que vienen de una
    atención apuntan a su operación; el administrativo no tiene operación
    y se prorratea entre las afiliaciones.
  - Costos de canal y otros: no tienen tipo propio; se agregan al CHECK de
    tipo_costo si se necesitan.
  - El criterio de prorrateo no se guarda en la base.


4.11 RESULTADO FINANCIERO POR ASEGURADO
---------------------------------------

Resultado financiero = Ingresos generados - Costos asociados, como
indicador de sostenibilidad (no de utilidad comercial). Se calcula por
asegurado, cobertura, segmento, canal / IPRESS y período. Se requiere
comparar períodos y calcular la razón de siniestralidad
(costo de prestaciones / ingresos por aportes).

  MODELO v2
  - Por asegurado, período y segmento: vistas vw_resultado_financiero,
    vw_resultado_financiero_mensual y vw_resultado_por_segmento_mensual.
    El segmento es el que tenía el asegurado en cada fecha.
  - Por cobertura: ingresos y costos -> afiliaciones -> coberturas.
  - Por canal: solo ingresos y costos vinculados a operaciones de ese
    canal. Los aportes y el costo administrativo no tienen canal.
  - Por IPRESS: fuera del alcance.
  - Razón de siniestralidad: se calcula con una consulta,
      costos PRESTACION + REFERENCIA_INTERINSTITUCIONAL
      dividido entre
      ingresos APORTE_ENTIDAD + APORTE_TITULAR,
    agrupando por mes, segmento o cobertura.


4.12 INFORMACIÓN TEMPORAL
-------------------------

Se requiere analizar por día, mes, trimestre y año, y la evolución de
asegurados, coberturas asignadas, topes y consumo, atenciones, ingresos,
costos y resultado financiero.

  MODELO v2
  - Tabla periodos: calendario diario con año, mes, día, trimestre y
    semestre.
  - Evolución de asegurados: fecha de alta e historial de condición.
  - Evolución de coberturas asignadas: fechas de afiliación y de baja.
  - Evolución de atenciones, ingresos, costos y resultado: por periodos.
  - Topes y consumo: fuera del alcance.


4.13 SEGMENTACIÓN DE ASEGURADOS
-------------------------------

Segmentos de ejemplo: titular activo, titular pensionista, derechohabiente
cónyuge, derechohabiente hijo, cesante con continuación voluntaria. La
clasificación puede cambiar con el tiempo y se desea comparar el resultado
entre segmentos.

  MODELO v2
  - Los datos de ejemplo usan 4 segmentos: titular activo, titular
    pensionista, derechohabiente y cesante. Separar derechohabiente
    cónyuge e hijo solo requiere agregar filas en segmentos.
  - El cambio de segmento se conserva en asegurados_condicion_hist, y la
    comparación usa el segmento de cada fecha.


==========================================================================
5. CUMPLIMIENTO DE LAS REGLAS DE NEGOCIO
==========================================================================

  SI       = implementado
  PARCIAL  = cubierto de forma simplificada
  NO       = fuera del alcance acotado

  SI       Un asegurado puede afiliarse a una o varias coberturas.
           (afiliaciones)
  SI       Una cobertura puede aplicar a muchos asegurados.
           (afiliaciones)
  NO       Un asegurado puede tener varios topes de cobertura.
  NO       Un tope puede tener uno o varios beneficiarios.
  NO       Un asegurado puede tener varias credenciales.
  NO       Una credencial pertenece a un único titular.
  PARCIAL  Un asegurado puede tener varias solicitudes de reembolso.
           (operaciones de tipo SOLICITUD_REEMBOLSO)
  SI       Una solicitud corresponde a una cobertura.
           (la operación se registra sobre una afiliación)
  SI       Una atención debe estar asociada a un canal.
           (operaciones.id_canal es obligatorio)
  SI       Una atención puede generar ingresos para el fondo.
           (recuperación por subrogación, ingresos.id_operacion)
  SI       Una atención puede generar costos para el fondo.
           (costos.id_operacion)
  SI       Los ingresos y costos deben poder analizarse por período.
           (periodos)
  SI       La clasificación de un asegurado puede cambiar en el tiempo.
           (asegurados_condicion_hist)
  NO       Los saldos de cobertura deben conservarse históricamente.
  SI       Un asegurado puede afiliarse nuevamente tras una baja.
           (clave única incluye la fecha de afiliación)
  SI       No todas las atenciones generan ingresos directos.
           (ingresos.id_operacion es opcional)
  SI       No todas las coberturas generan costos.
           (un costo no es obligatorio por afiliación)
  SI       Algunos costos pueden asignarse indirectamente.
           (costo ADMINISTRATIVO sin operación)
  SI       El resultado debe analizarse desde diferentes perspectivas.
           (asegurado, cobertura, segmento, entidad, canal, período)
  SI       La información histórica no debe perderse.
           (historial de segmento y entidad; los movimientos no se
           modifican cuando cambian los datos del asegurado)
  SI       El resultado es un indicador de sostenibilidad, no de ganancia.


==========================================================================
6. CUMPLIMIENTO DE LOS REQUERIMIENTOS DE ANÁLISIS
==========================================================================

   1. ¿Cuál es el resultado financiero total de cada asegurado?
      SI. vw_resultado_financiero agrupado por asegurado.
   2. ¿Cuáles son los 10 asegurados de mayor costo?
      SI. Suma de costos por asegurado, TOP 10.
   3. ¿Cuáles son los 10 asegurados más superavitarios?
      SI. vw_resultado_financiero, TOP 10 por resultado.
   4. ¿Qué coberturas generan mayor costo?
      SI. costos -> afiliaciones -> coberturas.
   5. ¿Qué asegurados tienen muchas atenciones pero bajo aporte?
      SI. Conteo de operaciones frente a suma de ingresos de aporte.
   6. ¿Qué segmento genera mayores ingresos?
      SI. vw_resultado_por_segmento_mensual.
   7. ¿Qué segmento tiene mejor resultado financiero?
      SI. vw_resultado_por_segmento_mensual.
   8. ¿Cuánto ingreso por aportes genera cada asegurado?
      SI. Ingresos APORTE_* -> afiliaciones -> asegurados.
   9. ¿Cuánto costo genera cada asegurado?
      SI. costos -> afiliaciones -> asegurados.
  10. ¿Cómo evoluciona el resultado de un asegurado mes a mes?
      SI. vw_resultado_financiero_mensual.
  11. ¿Qué canal / IPRESS genera mayor cantidad de atenciones?
      PARCIAL. Por canal sí; por IPRESS específica no.
  12. ¿Qué canal genera mejor resultado financiero?
      PARCIAL. Solo con ingresos y costos vinculados a operaciones; los
      aportes no tienen canal. La métrica más útil es el costo por
      operación de cada canal.
  13. ¿Qué coberturas generan ingresos pero también costos elevados?
      SI. Ingresos y costos por cobertura.
  14. ¿Qué asegurados pasaron de superavitarios a deficitarios?
      SI. Comparar el resultado entre dos períodos en la vista mensual.
  15. ¿Qué asegurados incrementaron su costo durante el último año?
      SI. Comparar costos de los últimos 12 meses con los 12 anteriores.
  16. ¿Es sostenible el fondo por segmento y por cobertura en el tiempo?
      SI. Resultado y razón de siniestralidad por segmento o cobertura y
      por mes.


==========================================================================
7. LÓGICA DE LAS RELACIONES
==========================================================================

Todas las relaciones son de uno a muchos (1:N). La relación muchos a
muchos entre asegurados y coberturas se resuelve con la tabla
afiliaciones.

Formato:  tabla padre -> tabla hija  (cardinalidad)
          Pregunta que responde.

  segmentos -> asegurados  (1:N)
      ¿Qué tipo de asegurado es hoy?

  entidades_empleadoras -> asegurados  (0..1:N)
      ¿Quién es hoy su empleador?

  asegurados -> asegurados_condicion_hist  (1:N)
      ¿Qué condición tuvo en cada fecha?

  segmentos -> asegurados_condicion_hist  (1:N)
      ¿En qué segmento estaba en una fecha dada?

  entidades_empleadoras -> asegurados_condicion_hist  (0..1:N)
      ¿Quién era su empleador en una fecha dada?

  categorias_cobertura -> coberturas  (1:N)
      ¿Cuánto se gasta por categoría (básica, complementaria, especial)?

  asegurados -> afiliaciones  (1:N)
      ¿Qué planes tiene cada asegurado?

  coberturas -> afiliaciones  (1:N)
      ¿Quiénes están afiliados a cada plan?

  afiliaciones -> operaciones  (1:N)
      ¿Qué atenciones tuvo el asegurado y bajo qué plan?

  canales -> operaciones  (1:N)
      ¿Por qué vía se atiende la gente?

  periodos -> operaciones  (1:N)
      ¿Cuántas atenciones hubo por mes?

  afiliaciones -> ingresos  (1:N)
      ¿Cuánto aportó cada asegurado y para qué plan?

  periodos -> ingresos  (1:N)
      ¿Cuánto se recaudó por mes?

  entidades_empleadoras -> ingresos  (0..1:N)
      ¿Cuánto pagó cada empleador?

  operaciones -> ingresos  (0..1:N)
      ¿Cuánto se recuperó de terceros por cada atención?

  afiliaciones -> costos  (1:N)
      ¿Cuánto costó cada asegurado, incluidos los gastos administrativos?

  operaciones -> costos  (0..1:N)
      ¿Cuánto costó cada atención?

  periodos -> costos  (1:N)
      ¿Cuánto se gastó por mes?

  cargas -> operaciones, ingresos y costos  (1:N)
      ¿De qué sistema y en qué carga llegó cada fila?


Caminos para responder cada análisis:

  Resultado por asegurado
      ingresos + costos -> afiliaciones -> asegurados
  Resultado por segmento
      ... -> asegurados -> asegurados_condicion_hist (por fecha) -> segmentos
  Resultado por cobertura
      ingresos + costos -> afiliaciones -> coberturas -> categorias_cobertura
  Aportes por entidad
      ingresos -> entidades_empleadoras
  Costo por canal
      costos -> operaciones -> canales
  Recuperaciones
      ingresos (subrogación) -> operaciones
  Evolución mensual
      ingresos / costos / operaciones -> periodos
  Trazabilidad
      ingresos / costos / operaciones -> cargas


==========================================================================
8. DECISIONES DE DISEÑO
==========================================================================

1. Los ingresos se relacionan con la afiliación, no con la operación.
   El aporte se paga por estar afiliado, se atienda o no el asegurado.
   Solo la recuperación por subrogación nace de una atención, y es el único
   ingreso que puede apuntar a una operación (lo controla un CHECK).

2. Ingresos, costos y operaciones no guardan id_asegurado ni id_cobertura.
   Ambos datos se obtienen de la afiliación. Guardarlos también en esas
   tablas permitiría que se contradijeran (tercera forma normal).

3. Claves foráneas compuestas (id_operacion, id_afiliacion).
   En ingresos y costos obligan a que la operación referenciada sea de la
   misma afiliación. Así un costo o una recuperación no pueden quedar
   asignados al asegurado equivocado.

4. Los costos tienen afiliación obligatoria y operación opcional.
   Todo costo pertenece a un asegurado, incluido el administrativo. Solo el
   administrativo puede no tener operación (lo controla un CHECK).

5. El historial de condición se cruza por fecha, sin clave foránea hacia
   los movimientos.
   La vista vw_resultado_financiero busca el tramo cuyo rango incluye la
   fecha de cada movimiento. Así no se repite el segmento en miles de filas
   y los reportes de meses pasados no cambian cuando el asegurado cambia de
   condición. asegurados.id_segmento e id_entidad se mantienen para
   consultar rápido la condición actual.

6. Sin trigger en el historial.
   Los tramos los carga el proceso de integración con las fechas del
   sistema fuente. Un trigger usaría la fecha de carga, que no es la fecha
   real del cambio.

7. codigo_origen único e id_carga en cada movimiento.
   Evitan duplicados al reprocesar y permiten rehacer un mes completo
   cuando el sistema fuente corrige datos. Los importes se mantienen
   mayores o iguales a cero: las correcciones se hacen recargando el mes.

8. periodos es un calendario diario.
   Las atenciones y liquidaciones ocurren en días concretos. Con el día
   guardado se puede agrupar por mes, trimestre o año; al revés no sería
   posible.

9. Se eliminaron columnas redundantes.
   asegurados.tipo_asegurado (lo da el segmento) y coberturas.tipo_cobertura
   (lo da la categoría).


==========================================================================
9. EXTENSIONES POSIBLES
==========================================================================

Para cubrir lo que quedó fuera del alcance acotado, sin cambiar las tablas
actuales:

  Topes y consumo
      topes_cobertura (tope por afiliación, monto, vigencia, estado)
      topes_beneficiarios (asegurados que comparten un tope)
      topes_saldos_hist (saldo disponible por fecha)

  Credenciales
      credenciales (número, afiliación, emisión, vencimiento, estado,
      tope de carta de garantía)
      id_credencial opcional en operaciones

  Reembolsos
      solicitudes_reembolso (operación, plazo, resolución, saldo)
      reembolso_componentes (monto reembolsado, descuentos, penalidades)

  IPRESS
      ipress (código, nombre, canal, ubicación)
      id_ipress en operaciones

  Grupo familiar
      id_titular en asegurados, para analizar el resultado por núcleo
      familiar

  Ubicación geográfica
      ubigeo en asegurados e ipress
