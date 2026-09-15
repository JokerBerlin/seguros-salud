Caso propuesto: Seguro de Salud Público — Resultado Financiero por Asegurado

1\. Contexto del negocio



FONASALUD es un fondo público de aseguramiento en salud que brinda cobertura médica a los trabajadores de una entidad del Estado y a sus derechohabientes, financiado con aportes de planilla, transferencias del Tesoro Público y aportes de pensionistas.



FONASALUD dispone de información distribuida en diferentes sistemas: afiliaciones, atenciones médicas en su red de IPRESS, solicitudes de reembolso, aportes recibidos y pagos realizados a prestadores de salud.



La gerencia necesita responder preguntas como:



¿Cuánto le cuesta cada asegurado al fondo? ¿Qué asegurados son superavitarios (aportan más de lo que consumen) y cuáles son deficitarios? ¿Qué coberturas generan mayor costo? ¿Qué segmento de asegurados genera mayores aportes? ¿Cuánto se paga por prestaciones a las IPRESS de la red? ¿Cuánto le cuesta al fondo mantener determinadas coberturas? ¿Cómo evoluciona el resultado financiero de un asegurado a lo largo del tiempo? ¿Es sostenible el fondo por segmento y por cobertura?



Para ello, se solicita diseñar una base de datos que permita centralizar esta información y posteriormente generar indicadores de costo y sostenibilidad financiera.



2\. Información de los asegurados



FONASALUD registra asegurados titulares (personal activo o pensionista) y sus derechohabientes, afiliados a través de la entidad empleadora a la que pertenece el titular.



Para cada asegurado se desea almacenar:



Código único del asegurado. Tipo de asegurado (titular activo / titular pensionista / derechohabiente). Documento de identidad. Nombres. Fecha de nacimiento. Sexo. Estado del asegurado. Fecha de alta. Segmento al que pertenece. Ubicación geográfica. Entidad empleadora a la que está vinculado, cuando corresponda. Canal principal utilizado por el asegurado.



Para cada entidad empleadora: código único, nombre de la entidad, sector o dependencia, fecha de registro, estado.



Un asegurado puede cambiar de segmento durante su relación con el fondo (por ejemplo, al pasar de titular activo a pensionista).



3\. Coberturas de salud



FONASALUD ofrece diferentes coberturas:



Cobertura Básica de Salud. Cobertura Complementaria Odontológica. Cobertura Complementaria Oncológica. Cobertura de Alto Costo. Cobertura para Pensionistas. Otras coberturas.



Cada cobertura pertenece a una determinada categoría (básica, complementaria, especial).



Para las coberturas se necesita registrar:



Código de la cobertura. Nombre. Categoría. Tipo. Estado. Fecha de vigencia. Aporte de referencia (porcentaje o monto fijado por norma). Moneda. Características de la cobertura (topes, copagos, periodos de carencia).



Una misma cobertura puede aplicar a muchos asegurados.



4\. Afiliación a coberturas



Cuando un asegurado queda comprendido en una cobertura, el fondo registra la relación entre el asegurado y dicha cobertura.



Por ejemplo: el asegurado Carlos Ramos queda afiliado a la Cobertura Básica de Salud y, al pasar a la condición de pensionista, se afilia adicionalmente a la Cobertura para Pensionistas.



Para cada afiliación se requiere conocer:



Asegurado. Cobertura asignada. Fecha de afiliación. Fecha de baja, si corresponde. Estado. Canal mediante el cual fue registrada. Dependencia relacionada, cuando corresponda. Condiciones aplicadas (aporte pactado, copago).



Un asegurado puede tener más de una afiliación a la misma cobertura a lo largo del tiempo (reingresos).



5\. Topes de cobertura y consumo



Los asegurados tienen topes de cobertura asociados a su afiliación, definidos por norma.



El fondo necesita conocer el consumo acumulado frente a esos topes y su evolución.



Para cada tope de cobertura se debe poder identificar:



Código de cobertura asignado. Asegurado o asegurados asociados (un núcleo familiar puede compartir tope entre titular y derechohabientes). Cobertura. Moneda. Fecha de inicio de vigencia. Fecha de fin de vigencia. Estado.



El fondo obtiene información periódica sobre el saldo disponible del tope.



Se requiere conservar el histórico de saldos, de manera que sea posible conocer cuánto tope le quedaba a un asegurado en una fecha determinada.



6\. Credenciales del asegurado



Un asegurado puede tener una o varias credenciales (física o virtual) asociadas a su afiliación.



Para cada credencial se registra:



Número identificador de la credencial. Asegurado titular. Cobertura asociada. Fecha de emisión. Fecha de vencimiento. Estado. Tope autorizado para carta de garantía.



Las credenciales generan diferentes tipos de movimientos: atenciones presenciales, autorizaciones de carta de garantía, anulaciones, otros movimientos.



Cada movimiento debe registrar su fecha, importe y demás información necesaria para su análisis.



7\. Solicitudes de reembolso



Los asegurados pueden solicitar el reembolso de gastos médicos pagados directamente cuando se atienden fuera de la red o de forma particular.



Para cada solicitud se necesita conocer:



Asegurado. Cobertura relacionada. Fecha de presentación. Monto solicitado. Moneda. Plazo de atención. Estado. Fecha de resolución. Saldo pendiente de pago.



Las solicitudes generan pagos, que pueden incluir:



Monto reembolsado. Descuento por evaluación administrativa. Penalidad por documentación incompleta. Otros conceptos.



El fondo necesita conservar el detalle de estos componentes.



8\. Atenciones y transacciones



Los asegurados reciben atenciones a través de diferentes canales:



IPRESS propias de la red. IPRESS de terceros mediante convenio o referencia. Telemedicina. Farmacia convenio. Atención domiciliaria.



Entre las prestaciones pueden encontrarse:



Consultas. Procedimientos. Exámenes auxiliares. Entrega de medicamentos. Hospitalizaciones. Emergencias.



Cada atención debe permitir identificar, cuando corresponda:



Asegurado involucrado. Cobertura relacionada. Fecha y hora. Tipo de prestación. Canal / IPRESS. Importe. Estado de la atención.



9\. Ingresos del fondo



Desde la perspectiva del fondo, los asegurados y entidades empleadoras generan diferentes tipos de ingresos.



Aportes, provenientes principalmente de:



Aporte del titular activo, descontado por planilla. Aporte de la entidad empleadora. Transferencias del Tesoro Público. Aporte del pensionista.



Otros ingresos, que pueden generarse por:



Recuperación o subrogación frente a terceros responsables. Reintegros y otros conceptos.



El fondo desea registrar los ingresos generados y poder relacionarlos con el asegurado y la cobertura correspondiente.



10\. Costos asociados



No todas las coberturas generan únicamente egresos previsibles: el fondo incurre en costos asociados a sus asegurados y coberturas.



Entre ellos pueden encontrarse:



Costos por prestaciones pagadas a las IPRESS de la red. Costos por referencias a otras instituciones (transferencias interinstitucionales). Costos de procesamiento de reembolsos. Costos de canales de atención. Costos administrativos. Otros costos asignables.



No necesariamente todos los costos se generan directamente por una atención específica. Algunos costos pueden distribuirse posteriormente utilizando criterios definidos por el área financiera.



11\. Resultado financiero por asegurado



El área financiera desea calcular el resultado financiero de cada asegurado, como indicador de sostenibilidad del fondo (no como utilidad comercial).



Resultado financiero = Ingresos generados (aportes y otros) − Costos asociados



Los ingresos pueden provenir de aportes, transferencias y recuperaciones. Los costos pueden estar relacionados directamente con un asegurado, cobertura, atención o período.



El fondo desea calcular el resultado financiero:



Por asegurado. Por cobertura. Por segmento. Por canal / IPRESS. Por período.



Además, necesita comparar el resultado financiero entre diferentes períodos y calcular la razón de siniestralidad (costo de prestaciones / ingresos por aportes) en cada corte, como señal de sostenibilidad del fondo.



12\. Información temporal



La gerencia desea analizar la evolución histórica.



Por ejemplo: el asegurado tenía un resultado financiero de S/ 120 en enero, S/ −60 en febrero y S/ 30 en marzo.



Por ello, el modelo debe permitir analizar la información por diferentes períodos:



Día. Mes. Trimestre. Año.



También se desea conocer la evolución de:



Asegurados. Coberturas asignadas. Topes y consumo. Atenciones. Ingresos. Costos. Resultado financiero.



13\. Segmentación de asegurados



El fondo clasifica a sus asegurados en diferentes segmentos, por ejemplo:



Titular activo. Titular pensionista. Derechohabiente cónyuge. Derechohabiente hijo. Cesante con continuación voluntaria.



La clasificación puede cambiar con el tiempo (por ejemplo, al pasar de activo a pensionista).



La gerencia desea comparar el resultado financiero de los diferentes segmentos.



14\. Requerimientos de análisis



El modelo resultante debe permitir responder preguntas como:



¿Cuál es el resultado financiero total generado por cada asegurado? ¿Cuáles son los 10 asegurados de mayor costo? ¿Cuáles son los 10 asegurados más superavitarios? ¿Qué coberturas generan mayor costo? ¿Qué asegurados tienen muchas atenciones pero bajo aporte? ¿Qué segmento genera mayores ingresos? ¿Qué segmento tiene mejor resultado financiero? ¿Cuánto ingreso por aportes genera cada asegurado? ¿Cuánto costo genera cada asegurado? ¿Cómo evoluciona el resultado financiero de un asegurado mes a mes? ¿Qué canal / IPRESS genera mayor cantidad de atenciones? ¿Qué canal genera mejor resultado financiero? ¿Qué coberturas generan ingresos pero también costos elevados? ¿Qué asegurados pasaron de ser superavitarios a deficitarios? ¿Qué asegurados incrementaron significativamente su costo durante el último año? ¿Es sostenible el fondo por segmento y por cobertura en el tiempo?



15\. Reglas de negocio iniciales



Los estudiantes deberán considerar, como mínimo, las siguientes reglas:



Un asegurado puede afiliarse a una o varias coberturas. Una cobertura puede aplicar a muchos asegurados. Un asegurado puede tener varios topes de cobertura. Un tope puede tener uno o varios beneficiarios. Un asegurado puede tener varias credenciales. Una credencial pertenece a un único titular. Un asegurado puede tener varias solicitudes de reembolso. Una solicitud corresponde a una cobertura. Una atención debe estar asociada a un canal. Una atención puede generar ingresos para el fondo. Una atención puede generar costos para el fondo. Los ingresos y costos deben poder analizarse por período. La clasificación de un asegurado puede cambiar a lo largo del tiempo. Los saldos de cobertura deben conservarse históricamente. Un asegurado puede afiliarse nuevamente a una cobertura después de haberse dado de baja. No todas las atenciones generan necesariamente ingresos directos. No todas las coberturas generan necesariamente costos. Algunos costos pueden ser asignados indirectamente a los asegurados. El resultado financiero debe poder analizarse desde diferentes perspectivas. La información histórica no debe perderse cuando cambien los datos actuales del asegurado. El fondo no distribuye utilidades: el resultado financiero es un indicador de sostenibilidad, no de ganancia.

