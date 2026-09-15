-- =====================================================================
-- Caso: FONASALUD — Resultado financiero por asegurado (seguro público)
-- Modelo físico — Microsoft SQL Server
-- Estructura: segmentos / asegurados / entidades_empleadoras /
--             categorias_cobertura / coberturas / afiliaciones /
--             canales / periodos / operaciones / ingresos / costos
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
    nombre        NVARCHAR(50)  NOT NULL,   -- BASICA / COMPLEMENTARIA / ESPECIAL
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
-- ---------------------------------------------------------------------

CREATE TABLE asegurados (
    id_asegurado      INT IDENTITY(1,1) PRIMARY KEY,
    codigo            VARCHAR(20)   NOT NULL UNIQUE,
    tipo_asegurado    VARCHAR(30)   NOT NULL,   -- TITULAR_ACTIVO / TITULAR_PENSIONISTA / DERECHOHABIENTE
    documento         VARCHAR(15)   NOT NULL UNIQUE,
    nombres           NVARCHAR(150) NOT NULL,
    fecha_nacimiento  DATE NOT NULL,
    sexo              CHAR(1) NOT NULL CHECK (sexo IN ('M','F')),
    fecha_alta        DATE NOT NULL,
    estado            VARCHAR(20)   NOT NULL DEFAULT 'ACTIVO',
    id_segmento       INT NOT NULL,
    id_entidad        INT NULL,                -- NULL si no está vinculado a una entidad empleadora (ej. cesante)
    CONSTRAINT fk_asegurado_segmento FOREIGN KEY (id_segmento) REFERENCES segmentos(id_segmento),
    CONSTRAINT fk_asegurado_entidad  FOREIGN KEY (id_entidad)  REFERENCES entidades_empleadoras(id_entidad)
);
GO

-- ---------------------------------------------------------------------
-- Coberturas de salud
-- ---------------------------------------------------------------------

CREATE TABLE coberturas (
    id_cobertura          INT IDENTITY(1,1) PRIMARY KEY,
    codigo                VARCHAR(20)   NOT NULL UNIQUE,
    nombre                NVARCHAR(100) NOT NULL,
    id_categoria          INT NOT NULL,
    tipo_cobertura        VARCHAR(30)   NOT NULL,  -- BASICA / COMPLEMENTARIA / ESPECIAL
    moneda                CHAR(3)  NOT NULL DEFAULT 'PEN',
    aporte_referencial    DECIMAL(10,2) NOT NULL CHECK (aporte_referencial >= 0), -- % o monto fijado por norma
    estado                VARCHAR(20)   NOT NULL DEFAULT 'VIGENTE',
    fecha_vigencia_desde  DATE NOT NULL,
    CONSTRAINT fk_cobertura_categoria FOREIGN KEY (id_categoria) REFERENCES categorias_cobertura(id_categoria)
);
GO

-- ---------------------------------------------------------------------
-- Afiliaciones (asegurado <-> cobertura, resuelve la N:M)
-- ---------------------------------------------------------------------

CREATE TABLE afiliaciones (
    id_afiliacion    BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_asegurado     INT NOT NULL,
    id_cobertura     INT NOT NULL,
    fecha_afiliacion DATE NOT NULL,
    fecha_baja       DATE NULL,
    estado           VARCHAR(20) NOT NULL DEFAULT 'VIGENTE',
    CONSTRAINT fk_afiliacion_asegurado FOREIGN KEY (id_asegurado) REFERENCES asegurados(id_asegurado),
    CONSTRAINT fk_afiliacion_cobertura FOREIGN KEY (id_cobertura) REFERENCES coberturas(id_cobertura),
    CONSTRAINT chk_afiliacion_fechas   CHECK (fecha_baja IS NULL OR fecha_baja >= fecha_afiliacion)
);
GO

CREATE INDEX idx_afiliacion_asegurado ON afiliaciones (id_asegurado);
CREATE INDEX idx_afiliacion_cobertura ON afiliaciones (id_cobertura);
GO

-- ---------------------------------------------------------------------
-- Operaciones (tabla genérica: atenciones médicas, reembolsos, etc.)
-- ---------------------------------------------------------------------

CREATE TABLE operaciones (
    id_operacion    BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_asegurado    INT NOT NULL,
    id_cobertura    INT NOT NULL,
    id_canal        INT NOT NULL,
    id_periodo      INT NOT NULL,
    tipo_operacion  VARCHAR(30) NOT NULL,  -- ATENCION_MEDICA / SOLICITUD_REEMBOLSO / CARTA_GARANTIA / ...
    importe         DECIMAL(12,2) NOT NULL CHECK (importe >= 0),
    estado          VARCHAR(20) NOT NULL DEFAULT 'REGISTRADA',
    CONSTRAINT fk_operacion_asegurado FOREIGN KEY (id_asegurado) REFERENCES asegurados(id_asegurado),
    CONSTRAINT fk_operacion_cobertura FOREIGN KEY (id_cobertura) REFERENCES coberturas(id_cobertura),
    CONSTRAINT fk_operacion_canal     FOREIGN KEY (id_canal)     REFERENCES canales(id_canal),
    CONSTRAINT fk_operacion_periodo   FOREIGN KEY (id_periodo)   REFERENCES periodos(id_periodo)
);
GO

CREATE INDEX idx_operacion_asegurado ON operaciones (id_asegurado);
CREATE INDEX idx_operacion_cobertura ON operaciones (id_cobertura);
CREATE INDEX idx_operacion_periodo   ON operaciones (id_periodo);
CREATE INDEX idx_operacion_canal     ON operaciones (id_canal);
GO

-- ---------------------------------------------------------------------
-- Ingresos (aportes, transferencias, recuperaciones)
-- ---------------------------------------------------------------------

CREATE TABLE ingresos (
    id_ingreso    BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_asegurado  INT NOT NULL,
    id_cobertura  INT NOT NULL,
    id_operacion  BIGINT NULL,      -- NULL cuando el ingreso no proviene de una operación puntual (ej. aporte mensual)
    id_periodo    INT NOT NULL,
    tipo_ingreso  VARCHAR(30) NOT NULL,  -- APORTE_TITULAR / APORTE_ENTIDAD / TRANSFERENCIA_TESORO / RECUPERACION_SUBROGACION
    importe       DECIMAL(12,2) NOT NULL CHECK (importe >= 0),
    CONSTRAINT fk_ingreso_asegurado FOREIGN KEY (id_asegurado) REFERENCES asegurados(id_asegurado),
    CONSTRAINT fk_ingreso_cobertura FOREIGN KEY (id_cobertura) REFERENCES coberturas(id_cobertura),
    CONSTRAINT fk_ingreso_operacion FOREIGN KEY (id_operacion) REFERENCES operaciones(id_operacion),
    CONSTRAINT fk_ingreso_periodo   FOREIGN KEY (id_periodo)   REFERENCES periodos(id_periodo)
);
GO

CREATE INDEX idx_ingreso_asegurado ON ingresos (id_asegurado);
CREATE INDEX idx_ingreso_cobertura ON ingresos (id_cobertura);
CREATE INDEX idx_ingreso_periodo   ON ingresos (id_periodo);
GO

-- ---------------------------------------------------------------------
-- Costos (prestaciones pagadas a IPRESS, referencias, administrativos)
-- ---------------------------------------------------------------------

CREATE TABLE costos (
    id_costo      BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_asegurado  INT NOT NULL,
    id_cobertura  INT NOT NULL,
    id_operacion  BIGINT NULL,      -- NULL cuando el costo se distribuye indirectamente
    id_periodo    INT NOT NULL,
    tipo_costo    VARCHAR(30) NOT NULL,  -- PRESTACION / REFERENCIA_INTERINSTITUCIONAL / PROCESAMIENTO_REEMBOLSO / ADMINISTRATIVO
    importe       DECIMAL(12,2) NOT NULL CHECK (importe >= 0),
    CONSTRAINT fk_costo_asegurado FOREIGN KEY (id_asegurado) REFERENCES asegurados(id_asegurado),
    CONSTRAINT fk_costo_cobertura FOREIGN KEY (id_cobertura) REFERENCES coberturas(id_cobertura),
    CONSTRAINT fk_costo_operacion FOREIGN KEY (id_operacion) REFERENCES operaciones(id_operacion),
    CONSTRAINT fk_costo_periodo   FOREIGN KEY (id_periodo)   REFERENCES periodos(id_periodo)
);
GO

CREATE INDEX idx_costo_asegurado ON costos (id_asegurado);
CREATE INDEX idx_costo_cobertura ON costos (id_cobertura);
CREATE INDEX idx_costo_periodo   ON costos (id_periodo);
GO

-- ---------------------------------------------------------------------
-- Resultado financiero por asegurado y periodo (vista)
-- ---------------------------------------------------------------------

CREATE VIEW vw_resultado_financiero AS
SELECT
    ap.id_asegurado,
    a.codigo AS codigo_asegurado,
    ap.id_periodo,
    per.anio,
    per.mes,
    COALESCE(ing.total_ingreso, 0) - COALESCE(cos.total_costo, 0) AS resultado_financiero
FROM (
    SELECT id_asegurado, id_periodo FROM ingresos
    UNION
    SELECT id_asegurado, id_periodo FROM costos
) ap
JOIN asegurados a   ON a.id_asegurado = ap.id_asegurado
JOIN periodos   per ON per.id_periodo = ap.id_periodo
LEFT JOIN (
    SELECT id_asegurado, id_periodo, SUM(importe) AS total_ingreso
    FROM ingresos GROUP BY id_asegurado, id_periodo
) ing ON ing.id_asegurado = ap.id_asegurado AND ing.id_periodo = ap.id_periodo
LEFT JOIN (
    SELECT id_asegurado, id_periodo, SUM(importe) AS total_costo
    FROM costos GROUP BY id_asegurado, id_periodo
) cos ON cos.id_asegurado = ap.id_asegurado AND cos.id_periodo = ap.id_periodo;
GO
