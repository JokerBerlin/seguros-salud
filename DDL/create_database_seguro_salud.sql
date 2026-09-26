-- =====================================================================
-- Caso: FONASALUD — Resultado financiero por asegurado (seguro público)
-- Modelo físico v2 (corregido) — Microsoft SQL Server 2016 SP1+
--
-- Cambios principales respecto a v1:
--   * INGRESOS se vincula a la AFILIACIÓN (asegurado + cobertura), no a la
--     operación. Solo la RECUPERACION_SUBROGACION puede referenciar una
--     operación, y se valida que sea de la misma afiliación.
--   * INGRESOS registra la entidad empleadora que pagó el aporte.
--   * COSTOS se vincula a la AFILIACIÓN y (salvo ADMINISTRATIVO) a la
--     OPERACIÓN que lo originó, con la misma validación de consistencia.
--   * OPERACIONES se vincula a la AFILIACIÓN (ya no a asegurado y cobertura
--     por separado): no se puede registrar una atención sin afiliación.
--   * Se eliminan columnas redundantes que podían contradecirse:
--     ingresos/costos.id_asegurado, id_cobertura; operaciones.id_asegurado,
--     id_cobertura; asegurados.tipo_asegurado; coberturas.tipo_cobertura.
--   * Dominios cerrados con CHECK y unicidad de afiliaciones.
--   * Historial de segmento y entidad empleadora del asegurado
--     (asegurados_condicion_hist) para reportes por periodo.
--   * Base analítica alimentada por cargas: una fila por atención/pago,
--     con codigo_origen único e id_carga para no duplicar al reprocesar.
-- =====================================================================

CREATE DATABASE seguro_salud_publico;
GO
USE seguro_salud_publico;
GO

-- ---------------------------------------------------------------------
-- Tablas de referencia
-- ---------------------------------------------------------------------

CREATE TABLE segmentos (
    id_segmento   INT IDENTITY(1,1) PRIMARY KEY,
    codigo        VARCHAR(10)   NOT NULL UNIQUE,
    descripcion   NVARCHAR(100) NOT NULL   -- TITULAR_ACTIVO / TITULAR_PENSIONISTA / DERECHOHABIENTE / CESANTE
);
GO

CREATE TABLE categorias_cobertura (
    id_categoria  INT IDENTITY(1,1) PRIMARY KEY,
    nombre        NVARCHAR(50)  NOT NULL UNIQUE,   -- BASICA / COMPLEMENTARIA / ESPECIAL
    descripcion   NVARCHAR(150) NULL
);
GO

CREATE TABLE canales (
    id_canal      INT IDENTITY(1,1) PRIMARY KEY,
    codigo        VARCHAR(10)   NOT NULL UNIQUE,
    nombre        NVARCHAR(50)  NOT NULL,   -- IPRESS_RED / IPRESS_REFERENCIA / TELEMEDICINA / FARMACIA_CONVENIO / DOMICILIO
    descripcion   NVARCHAR(100) NULL
);
GO

CREATE TABLE periodos (
    id_periodo    INT IDENTITY(1,1) PRIMARY KEY,
    fecha         DATE NOT NULL UNIQUE,
    anio          SMALLINT NOT NULL,
    mes           TINYINT  NOT NULL CHECK (mes BETWEEN 1 AND 12),
    dia           TINYINT  NOT NULL CHECK (dia BETWEEN 1 AND 31),
    trimestre     TINYINT  NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    semestre      TINYINT  NOT NULL CHECK (semestre BETWEEN 1 AND 2)
);
GO

-- ---------------------------------------------------------------------
-- Entidades empleadoras (dependencias del Estado que afilian titulares)
-- ---------------------------------------------------------------------

CREATE TABLE entidades_empleadoras (
    id_entidad       INT IDENTITY(1,1) PRIMARY KEY,
    codigo           VARCHAR(20)   NOT NULL UNIQUE,
    nombre_entidad   NVARCHAR(150) NOT NULL,
    ruc              CHAR(11)      NOT NULL UNIQUE,
    sector           NVARCHAR(50)  NULL,
    fecha_registro   DATE NOT NULL,
    estado           VARCHAR(20)   NOT NULL DEFAULT 'ACTIVA'
);
GO

-- ---------------------------------------------------------------------
-- Asegurados
--   v2: se elimina tipo_asegurado (duplicaba segmentos.descripcion)
-- ---------------------------------------------------------------------

CREATE TABLE asegurados (
    id_asegurado      INT IDENTITY(1,1) PRIMARY KEY,
    codigo            VARCHAR(20)   NOT NULL UNIQUE,
    documento         VARCHAR(15)   NOT NULL UNIQUE,
    nombres           NVARCHAR(150) NOT NULL,
    fecha_nacimiento  DATE NOT NULL,
    sexo              CHAR(1) NOT NULL CHECK (sexo IN ('M','F')),
    fecha_alta        DATE NOT NULL,
    estado            VARCHAR(20)   NOT NULL DEFAULT 'ACTIVO',
    id_segmento       INT NOT NULL,            -- define el tipo de asegurado
    id_entidad        INT NULL,                -- empleador actual; NULL si es cesante / derechohabiente
    CONSTRAINT fk_asegurado_segmento FOREIGN KEY (id_segmento) REFERENCES segmentos(id_segmento),
    CONSTRAINT fk_asegurado_entidad  FOREIGN KEY (id_entidad)  REFERENCES entidades_empleadoras(id_entidad)
);
GO

CREATE INDEX idx_asegurado_segmento ON asegurados (id_segmento);
CREATE INDEX idx_asegurado_entidad  ON asegurados (id_entidad);
GO

-- ---------------------------------------------------------------------
-- Historial de condición del asegurado (segmento + entidad empleadora)
--   asegurados.id_segmento / id_entidad guardan solo el valor ACTUAL.
--   Esta tabla guarda cada tramo de tiempo para que los reportes de
--   periodos pasados usen el segmento y la entidad que regían entonces.
--   La llena el proceso de carga con las fechas del sistema origen
--   (no un trigger: la fecha de carga no es la fecha real del cambio).
-- ---------------------------------------------------------------------

CREATE TABLE asegurados_condicion_hist (
    id_hist       BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_asegurado  INT  NOT NULL,
    id_segmento   INT  NOT NULL,
    id_entidad    INT  NULL,
    fecha_desde   DATE NOT NULL,
    fecha_hasta   DATE NULL,              -- NULL = tramo vigente
    CONSTRAINT fk_hist_asegurado FOREIGN KEY (id_asegurado) REFERENCES asegurados(id_asegurado),
    CONSTRAINT fk_hist_segmento  FOREIGN KEY (id_segmento)  REFERENCES segmentos(id_segmento),
    CONSTRAINT fk_hist_entidad   FOREIGN KEY (id_entidad)   REFERENCES entidades_empleadoras(id_entidad),
    CONSTRAINT chk_hist_fechas   CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde),
    CONSTRAINT uq_hist_tramo     UNIQUE (id_asegurado, fecha_desde)
);
GO

-- Un solo tramo vigente por asegurado
CREATE UNIQUE INDEX uq_hist_vigente ON asegurados_condicion_hist (id_asegurado) WHERE fecha_hasta IS NULL;
CREATE INDEX idx_hist_segmento ON asegurados_condicion_hist (id_segmento);
GO

-- ---------------------------------------------------------------------
-- Coberturas de salud
--   v2: se elimina tipo_cobertura (duplicaba categorias_cobertura.nombre)
-- ---------------------------------------------------------------------

CREATE TABLE coberturas (
    id_cobertura          INT IDENTITY(1,1) PRIMARY KEY,
    codigo                VARCHAR(20)   NOT NULL UNIQUE,
    nombre                NVARCHAR(100) NOT NULL,
    id_categoria          INT NOT NULL,            -- BASICA / COMPLEMENTARIA / ESPECIAL
    moneda                CHAR(3)  NOT NULL DEFAULT 'PEN',
    aporte_referencial    DECIMAL(10,2) NOT NULL CHECK (aporte_referencial >= 0), -- % o monto fijado por norma
    estado                VARCHAR(20)   NOT NULL DEFAULT 'VIGENTE',
    fecha_vigencia_desde  DATE NOT NULL,
    CONSTRAINT fk_cobertura_categoria FOREIGN KEY (id_categoria) REFERENCES categorias_cobertura(id_categoria)
);
GO

CREATE INDEX idx_cobertura_categoria ON coberturas (id_categoria);
GO

-- ---------------------------------------------------------------------
-- Afiliaciones (asegurado <-> cobertura). Eje del modelo financiero:
-- ingresos, operaciones y costos cuelgan de aquí.
-- ---------------------------------------------------------------------

CREATE TABLE afiliaciones (
    id_afiliacion    BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_asegurado     INT NOT NULL,
    id_cobertura     INT NOT NULL,
    fecha_afiliacion DATE NOT NULL,
    fecha_baja       DATE NULL,
    estado           VARCHAR(20) NOT NULL DEFAULT 'VIGENTE'
                     CHECK (estado IN ('VIGENTE','SUSPENDIDA','BAJA')),
    CONSTRAINT fk_afiliacion_asegurado FOREIGN KEY (id_asegurado) REFERENCES asegurados(id_asegurado),
    CONSTRAINT fk_afiliacion_cobertura FOREIGN KEY (id_cobertura) REFERENCES coberturas(id_cobertura),
    CONSTRAINT chk_afiliacion_fechas   CHECK (fecha_baja IS NULL OR fecha_baja >= fecha_afiliacion),
    CONSTRAINT uq_afiliacion           UNIQUE (id_asegurado, id_cobertura, fecha_afiliacion)
);
GO

-- Un asegurado no puede tener dos afiliaciones abiertas a la misma cobertura
CREATE UNIQUE INDEX uq_afiliacion_abierta
    ON afiliaciones (id_asegurado, id_cobertura)
    WHERE fecha_baja IS NULL;
CREATE INDEX idx_afiliacion_cobertura ON afiliaciones (id_cobertura);
GO

-- ---------------------------------------------------------------------
-- Control de cargas (la base se alimenta de los sistemas origen)
--   Cada fila de operaciones, ingresos y costos indica en qué carga llegó
--   y trae su código del sistema origen (UNIQUE), para que una carga
--   repetida o un reproceso no duplique montos.
-- ---------------------------------------------------------------------

CREATE TABLE cargas (
    id_carga         INT IDENTITY(1,1) PRIMARY KEY,
    sistema_origen   VARCHAR(30) NOT NULL,     -- p. ej. ATENCIONES / RECAUDACION / CONTABILIDAD
    tabla_destino    VARCHAR(30) NOT NULL
                     CHECK (tabla_destino IN ('operaciones','ingresos','costos','asegurados_condicion_hist')),
    periodo_desde    DATE NOT NULL,
    periodo_hasta    DATE NOT NULL,
    fecha_inicio     DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    fecha_fin        DATETIME2(0) NULL,
    filas_leidas     INT NULL,
    filas_cargadas   INT NULL,
    filas_rechazadas INT NULL,
    estado           VARCHAR(15) NOT NULL DEFAULT 'EN_PROCESO'
                     CHECK (estado IN ('EN_PROCESO','COMPLETADA','FALLIDA','REVERTIDA')),
    CONSTRAINT chk_carga_periodo CHECK (periodo_hasta >= periodo_desde)
);
GO

-- ---------------------------------------------------------------------
-- Operaciones (atenciones médicas, reembolsos, cartas de garantía...)
--   v2: id_asegurado + id_cobertura  ->  id_afiliacion
--       importe -> importe_bruto (monto facturado/solicitado; el costo
--       reconocido se registra en COSTOS para no contarlo dos veces)
-- ---------------------------------------------------------------------

CREATE TABLE operaciones (
    id_operacion    BIGINT IDENTITY(1,1) PRIMARY KEY,
    codigo_origen   VARCHAR(40) NOT NULL,  -- n.º de atención en el sistema origen
    id_carga        INT NOT NULL,
    id_afiliacion   BIGINT NOT NULL,
    id_canal        INT NOT NULL,
    id_periodo      INT NOT NULL,
    tipo_operacion  VARCHAR(30) NOT NULL,  -- ATENCION_MEDICA / SOLICITUD_REEMBOLSO / CARTA_GARANTIA / ...
    importe_bruto   DECIMAL(12,2) NOT NULL CHECK (importe_bruto >= 0),
    estado          VARCHAR(20) NOT NULL DEFAULT 'REGISTRADA',
    CONSTRAINT fk_operacion_afiliacion FOREIGN KEY (id_afiliacion) REFERENCES afiliaciones(id_afiliacion),
    CONSTRAINT fk_operacion_canal      FOREIGN KEY (id_canal)      REFERENCES canales(id_canal),
    CONSTRAINT fk_operacion_periodo    FOREIGN KEY (id_periodo)    REFERENCES periodos(id_periodo),
    CONSTRAINT fk_operacion_carga      FOREIGN KEY (id_carga)      REFERENCES cargas(id_carga),
    CONSTRAINT uq_operacion_origen     UNIQUE (codigo_origen),
    -- Clave alterna para que ingresos/costos validen (operación, afiliación)
    CONSTRAINT uq_operacion_afiliacion UNIQUE (id_operacion, id_afiliacion)
);
GO

CREATE INDEX idx_operacion_afiliacion ON operaciones (id_afiliacion);
CREATE INDEX idx_operacion_periodo    ON operaciones (id_periodo);
CREATE INDEX idx_operacion_canal      ON operaciones (id_canal);
CREATE INDEX idx_operacion_carga      ON operaciones (id_carga);
GO

-- ---------------------------------------------------------------------
-- Ingresos (aportes, transferencias, recuperaciones)
--   v2: pertenecen a la AFILIACIÓN del asegurado.
--       id_entidad_pagadora: quién pagó (obligatorio en APORTE_ENTIDAD).
--       id_operacion: solo para RECUPERACION_SUBROGACION y debe ser una
--       operación de la misma afiliación (FK compuesta).
-- ---------------------------------------------------------------------

CREATE TABLE ingresos (
    id_ingreso           BIGINT IDENTITY(1,1) PRIMARY KEY,
    codigo_origen        VARCHAR(40) NOT NULL,  -- n.º de recibo / pago en el sistema origen
    id_carga             INT NOT NULL,
    id_afiliacion        BIGINT NOT NULL,
    id_periodo           INT NOT NULL,
    id_entidad_pagadora  INT NULL,
    id_operacion         BIGINT NULL,
    tipo_ingreso         VARCHAR(30) NOT NULL
                         CHECK (tipo_ingreso IN ('APORTE_TITULAR','APORTE_ENTIDAD',
                                                 'TRANSFERENCIA_TESORO','RECUPERACION_SUBROGACION')),
    importe              DECIMAL(12,2) NOT NULL CHECK (importe >= 0),
    CONSTRAINT fk_ingreso_afiliacion FOREIGN KEY (id_afiliacion)       REFERENCES afiliaciones(id_afiliacion),
    CONSTRAINT fk_ingreso_periodo    FOREIGN KEY (id_periodo)          REFERENCES periodos(id_periodo),
    CONSTRAINT fk_ingreso_entidad    FOREIGN KEY (id_entidad_pagadora) REFERENCES entidades_empleadoras(id_entidad),
    CONSTRAINT fk_ingreso_carga      FOREIGN KEY (id_carga)            REFERENCES cargas(id_carga),
    CONSTRAINT uq_ingreso_origen     UNIQUE (codigo_origen),
    CONSTRAINT fk_ingreso_operacion  FOREIGN KEY (id_operacion, id_afiliacion)
                                     REFERENCES operaciones(id_operacion, id_afiliacion),
    CONSTRAINT chk_ingreso_entidad   CHECK (tipo_ingreso <> 'APORTE_ENTIDAD' OR id_entidad_pagadora IS NOT NULL),
    CONSTRAINT chk_ingreso_operacion CHECK (id_operacion IS NULL OR tipo_ingreso = 'RECUPERACION_SUBROGACION')
);
GO

CREATE INDEX idx_ingreso_afiliacion ON ingresos (id_afiliacion, id_periodo);
CREATE INDEX idx_ingreso_periodo    ON ingresos (id_periodo);
CREATE INDEX idx_ingreso_entidad    ON ingresos (id_entidad_pagadora);
CREATE INDEX idx_ingreso_operacion  ON ingresos (id_operacion);
CREATE INDEX idx_ingreso_carga      ON ingresos (id_carga);
GO

-- ---------------------------------------------------------------------
-- Costos (prestaciones pagadas a IPRESS, referencias, administrativos)
--   v2: se imputan a la AFILIACIÓN. Todo costo que no sea ADMINISTRATIVO
--       debe venir de una operación de esa misma afiliación.
-- ---------------------------------------------------------------------

CREATE TABLE costos (
    id_costo       BIGINT IDENTITY(1,1) PRIMARY KEY,
    codigo_origen  VARCHAR(40) NOT NULL,  -- n.º de liquidación / asiento en el sistema origen
    id_carga       INT NOT NULL,
    id_afiliacion  BIGINT NOT NULL,
    id_periodo     INT NOT NULL,
    id_operacion   BIGINT NULL,          -- NULL solo en costos administrativos prorrateados
    tipo_costo     VARCHAR(30) NOT NULL
                   CHECK (tipo_costo IN ('PRESTACION','REFERENCIA_INTERINSTITUCIONAL',
                                         'PROCESAMIENTO_REEMBOLSO','ADMINISTRATIVO')),
    importe        DECIMAL(12,2) NOT NULL CHECK (importe >= 0),
    CONSTRAINT fk_costo_afiliacion FOREIGN KEY (id_afiliacion) REFERENCES afiliaciones(id_afiliacion),
    CONSTRAINT fk_costo_periodo    FOREIGN KEY (id_periodo)    REFERENCES periodos(id_periodo),
    CONSTRAINT fk_costo_carga      FOREIGN KEY (id_carga)      REFERENCES cargas(id_carga),
    CONSTRAINT uq_costo_origen     UNIQUE (codigo_origen),
    CONSTRAINT fk_costo_operacion  FOREIGN KEY (id_operacion, id_afiliacion)
                                   REFERENCES operaciones(id_operacion, id_afiliacion),
    CONSTRAINT chk_costo_operacion CHECK (tipo_costo = 'ADMINISTRATIVO' OR id_operacion IS NOT NULL)
);
GO

CREATE INDEX idx_costo_afiliacion ON costos (id_afiliacion, id_periodo);
CREATE INDEX idx_costo_periodo    ON costos (id_periodo);
CREATE INDEX idx_costo_operacion  ON costos (id_operacion);
CREATE INDEX idx_costo_carga      ON costos (id_carga);
GO

-- ---------------------------------------------------------------------
-- Correcciones del sistema origen (anulaciones, montos corregidos)
--   Los importes siguen siendo >= 0: no se cargan extornos negativos.
--   Si el origen corrige un mes ya cargado, se recarga ese mes:
--
--   BEGIN TRAN;
--     -- 1. ingresos y costos del mes (primero, porque apuntan a operaciones)
--     DELETE i FROM ingresos i JOIN periodos p ON p.id_periodo = i.id_periodo
--      WHERE p.anio = @anio AND p.mes = @mes;
--     DELETE c FROM costos c JOIN periodos p ON p.id_periodo = c.id_periodo
--      WHERE p.anio = @anio AND p.mes = @mes;
--     -- 2. operaciones: MERGE por codigo_origen (actualiza, inserta y
--     --    borra las anuladas que ya no tengan ingresos/costos asociados)
--     -- 3. volver a insertar ingresos y costos del mes desde el origen
--     -- 4. registrar la carga en CARGAS y marcar la anterior como REVERTIDA
--   COMMIT;
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Resultado financiero por asegurado y periodo
--   El asegurado se obtiene siempre a través de la afiliación.
--   Segmento y entidad son los que regían en la fecha del periodo
--   (asegurados_condicion_hist), no los actuales.
-- ---------------------------------------------------------------------

CREATE VIEW vw_resultado_financiero AS
WITH mov AS (
    SELECT af.id_asegurado, i.id_periodo, i.importe AS ingreso, CAST(0 AS DECIMAL(12,2)) AS costo
    FROM ingresos i
    JOIN afiliaciones af ON af.id_afiliacion = i.id_afiliacion
    UNION ALL
    SELECT af.id_asegurado, c.id_periodo, CAST(0 AS DECIMAL(12,2)), c.importe
    FROM costos c
    JOIN afiliaciones af ON af.id_afiliacion = c.id_afiliacion
),
res AS (
    SELECT id_asegurado, id_periodo, SUM(ingreso) AS total_ingreso, SUM(costo) AS total_costo
    FROM mov
    GROUP BY id_asegurado, id_periodo
)
SELECT
    r.id_asegurado,
    a.codigo      AS codigo_asegurado,
    r.id_periodo,
    per.fecha,
    per.anio,
    per.mes,
    h.id_segmento,                 -- segmento vigente en esa fecha
    h.id_entidad,                  -- entidad empleadora vigente en esa fecha
    r.total_ingreso,
    r.total_costo,
    r.total_ingreso - r.total_costo AS resultado_financiero
FROM res r
JOIN asegurados a   ON a.id_asegurado = r.id_asegurado
JOIN periodos   per ON per.id_periodo = r.id_periodo
LEFT JOIN asegurados_condicion_hist h
       ON h.id_asegurado = r.id_asegurado
      AND per.fecha >= h.fecha_desde
      AND (h.fecha_hasta IS NULL OR per.fecha <= h.fecha_hasta);
GO

-- Por asegurado y mes (si cambió de segmento a mitad de mes, salen dos filas)
CREATE VIEW vw_resultado_financiero_mensual AS
SELECT
    id_asegurado,
    codigo_asegurado,
    anio,
    mes,
    id_segmento,
    id_entidad,
    SUM(total_ingreso)        AS total_ingreso,
    SUM(total_costo)          AS total_costo,
    SUM(resultado_financiero) AS resultado_financiero
FROM vw_resultado_financiero
GROUP BY id_asegurado, codigo_asegurado, anio, mes, id_segmento, id_entidad;
GO

-- Por segmento y mes, con el segmento histórico
CREATE VIEW vw_resultado_por_segmento_mensual AS
SELECT
    r.anio,
    r.mes,
    r.id_segmento,
    s.descripcion                  AS segmento,
    COUNT(DISTINCT r.id_asegurado) AS asegurados,
    SUM(r.total_ingreso)           AS total_ingreso,
    SUM(r.total_costo)             AS total_costo,
    SUM(r.resultado_financiero)    AS resultado_financiero
FROM vw_resultado_financiero r
LEFT JOIN segmentos s ON s.id_segmento = r.id_segmento
GROUP BY r.anio, r.mes, r.id_segmento, s.descripcion;
GO
