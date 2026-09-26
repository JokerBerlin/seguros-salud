-- =====================================================================
-- FONASALUD v2 — Datos ficticios pero consistentes para reportes
-- Base: seguro_salud_publico (crear antes con seguro_salud_publico_v2.sql)
--
-- Qué genera (con los parámetros por defecto):
--   * Calendario diario 2025-01-01 a 2026-12-31 (tabla periodos).
--   * Movimientos de 2025-01 a 2026-08 (último mes cerrado).
--   * 40 entidades empleadoras y 2 000 asegurados en 4 segmentos.
--   * Historial de condición: jubilaciones, ceses y cambios de empleador
--     ocurridos dentro del periodo, para que el reporte por segmento
--     histórico se diferencie del segmento actual.
--   * Afiliación básica para todos y 0-3 coberturas adicionales.
--   * ~60 000 atenciones (una fila por atención) con su costo, aportes
--     mensuales, transferencias del Tesoro, recuperaciones por
--     subrogación y costos administrativos trimestrales prorrateados.
--   * Una carga por mes y tabla (más una carga FALLIDA de ejemplo).
--
-- Es determinista: misma @Seed = mismos datos. No escribe IDs a mano:
-- todo se relaciona por código, así que funciona aunque los IDENTITY
-- no empiecen en 1.
-- =====================================================================

USE seguro_salud_publico;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Seed              INT  = 20260925;
DECLARE @NumAsegurados     INT  = 2000;
DECLARE @NumEntidades      INT  = 40;
DECLARE @TargetOperaciones INT  = 60000;
DECLARE @CalDesde          DATE = '2025-01-01';   -- calendario (periodos)
DECLARE @CalHasta          DATE = '2026-12-31';
DECLARE @Desde             DATE = '2025-01-01';   -- movimientos
DECLARE @DatosHasta        DATE = '2026-08-31';   -- último mes cerrado
DECLARE @NumMeses          INT  = DATEDIFF(MONTH, @Desde, @DatosHasta) + 1;
DECLARE @UltimaAfiliacion  DATE = DATEADD(MONTH, -2, @DatosHasta);

DROP TABLE IF EXISTS #Tally, #Meses, #EntMap, #AseGen, #Ase, #Afi, #CargaMes,
                     #OpCtx, #OpGen, #Op, #CostoGen, #IngGen;

------------------------------------------------------------
-- 0. LIMPIEZA (orden inverso a las claves foráneas)
--    Si NO desea borrar datos existentes, elimine esta sección.
------------------------------------------------------------
BEGIN TRY
    BEGIN TRAN;
    DELETE FROM costos;
    DELETE FROM ingresos;
    DELETE FROM operaciones;
    DELETE FROM afiliaciones;
    DELETE FROM asegurados_condicion_hist;
    DELETE FROM asegurados;
    DELETE FROM coberturas;
    DELETE FROM categorias_cobertura;
    DELETE FROM entidades_empleadoras;
    DELETE FROM canales;
    DELETE FROM periodos;
    DELETE FROM segmentos;
    DELETE FROM cargas;
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH;

-- Reinicia IDENTITY solo en tablas que ya tuvieron filas.
-- (En una tabla recién creada, RESEED 0 haría que el primer id fuera 0.)
DECLARE @Tablas TABLE (orden INT IDENTITY(1,1), nombre SYSNAME);
INSERT INTO @Tablas (nombre)
VALUES ('costos'),('ingresos'),('operaciones'),('afiliaciones'),('asegurados_condicion_hist'),
       ('asegurados'),('coberturas'),('categorias_cobertura'),('entidades_empleadoras'),
       ('canales'),('periodos'),('segmentos'),('cargas');

DECLARE @i INT = 1, @nTablas INT = (SELECT COUNT(*) FROM @Tablas), @t SYSNAME, @sql NVARCHAR(300);
WHILE @i <= @nTablas
BEGIN
    SELECT @t = nombre FROM @Tablas WHERE orden = @i;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(@t)) IS NOT NULL
    BEGIN
        SET @sql = N'DBCC CHECKIDENT (''' + @t + N''', RESEED, 0) WITH NO_INFOMSGS;';
        EXEC sp_executesql @sql;
    END;
    SET @i += 1;
END;

------------------------------------------------------------
-- 1. TABLA TALLY (1..100 000)
------------------------------------------------------------
;WITH E1(n) AS (SELECT 1 FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) v(n)),
      E2(n) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
      E4(n) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b)
SELECT TOP (100000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
INTO #Tally
FROM E4 a CROSS JOIN E1 b;

CREATE UNIQUE CLUSTERED INDEX IX_Tally_n ON #Tally (n);

-- Aleatorio determinista: (CHECKSUM(CONCAT(@Seed, '-etiqueta-', clave)) & 2147483647) % m
-- El "& 2147483647" evita el desborde de ABS() cuando CHECKSUM devuelve -2147483648.

BEGIN TRY
BEGIN TRAN;

------------------------------------------------------------
-- 2. CATÁLOGOS
------------------------------------------------------------
INSERT INTO segmentos (codigo, descripcion)
VALUES ('TIT_ACT', N'TITULAR_ACTIVO'),
       ('TIT_PEN', N'TITULAR_PENSIONISTA'),
       ('DERHAB',  N'DERECHOHABIENTE'),
       ('CESANTE', N'CESANTE');

INSERT INTO categorias_cobertura (nombre, descripcion)
VALUES (N'BASICA',         N'Cobertura obligatoria financiada con aportes'),
       (N'COMPLEMENTARIA', N'Coberturas voluntarias pagadas por el titular'),
       (N'ESPECIAL',       N'Coberturas de alto costo y enfermedades catastróficas');

INSERT INTO canales (codigo, nombre, descripcion)
VALUES ('IPR_RED',  N'IPRESS_RED',        N'Establecimientos de la red propia'),
       ('IPR_REF',  N'IPRESS_REFERENCIA', N'Establecimientos externos por referencia'),
       ('TELEMED',  N'TELEMEDICINA',      N'Consulta remota'),
       ('FARMACIA', N'FARMACIA_CONVENIO', N'Farmacias con convenio'),
       ('DOMIC',    N'DOMICILIO',         N'Atención en el domicilio del asegurado');

INSERT INTO coberturas (codigo, nombre, id_categoria, moneda, aporte_referencial, estado, fecha_vigencia_desde)
SELECT v.codigo, v.nombre, c.id_categoria, 'PEN', v.aporte, 'VIGENTE', '2012-01-01'
FROM (VALUES ('BAS-01', N'Plan de salud básico',      N'BASICA',         185.00),
             ('COM-01', N'Salud dental',              N'COMPLEMENTARIA',  28.00),
             ('COM-02', N'Salud visual',              N'COMPLEMENTARIA',  18.00),
             ('COM-03', N'Atención domiciliaria',     N'COMPLEMENTARIA',  35.00),
             ('ESP-01', N'Oncología',                 N'ESPECIAL',        55.00),
             ('ESP-02', N'Alto costo y trasplantes',  N'ESPECIAL',        70.00)
     ) v (codigo, nombre, categoria, aporte)
JOIN categorias_cobertura c ON c.nombre = v.categoria;

------------------------------------------------------------
-- 3. PERIODOS (calendario diario)
------------------------------------------------------------
INSERT INTO periodos (fecha, anio, mes, dia, trimestre, semestre)
SELECT d.fecha, YEAR(d.fecha), MONTH(d.fecha), DAY(d.fecha), DATEPART(QUARTER, d.fecha),
       CASE WHEN MONTH(d.fecha) <= 6 THEN 1 ELSE 2 END
FROM #Tally t
CROSS APPLY (SELECT DATEADD(DAY, t.n - 1, @CalDesde) AS fecha) d
WHERE t.n <= DATEDIFF(DAY, @CalDesde, @CalHasta) + 1;

SELECT DATEFROMPARTS(anio, mes, 1) AS mes_ini, EOMONTH(fecha) AS mes_fin
INTO #Meses
FROM periodos
WHERE dia = 1 AND fecha BETWEEN @Desde AND @DatosHasta;

------------------------------------------------------------
-- 4. ENTIDADES EMPLEADORAS (ficticias)
------------------------------------------------------------
DECLARE @Sectores TABLE (id INT PRIMARY KEY, sector NVARCHAR(50));
INSERT INTO @Sectores
VALUES (0, N'Salud'), (1, N'Educación'), (2, N'Interior'), (3, N'Economía y Finanzas'),
       (4, N'Gobierno Regional'), (5, N'Gobierno Local'), (6, N'Justicia'), (7, N'Transportes');

INSERT INTO entidades_empleadoras (codigo, nombre_entidad, ruc, sector, fecha_registro, estado)
SELECT CONCAT('ENT', RIGHT('000' + CAST(t.n AS VARCHAR(3)), 3)),
       CONCAT(N'Entidad Pública Ficticia ', RIGHT('000' + CAST(t.n AS VARCHAR(3)), 3), N' - ', s.sector),
       CONCAT('20', CAST(600000000 + t.n * 7919 AS VARCHAR(9))),
       s.sector,
       DATEADD(DAY, (CHECKSUM(CONCAT(@Seed, '-ENTREG-', t.n)) & 2147483647) % 2500, CAST('2005-01-01' AS DATE)),
       'ACTIVA'
FROM #Tally t
JOIN @Sectores s ON s.id = (CHECKSUM(CONCAT(@Seed, '-SECTOR-', t.n)) & 2147483647) % 8
WHERE t.n <= @NumEntidades;

SELECT CAST(RIGHT(codigo, 3) AS INT) AS rn, id_entidad
INTO #EntMap
FROM entidades_empleadoras;

------------------------------------------------------------
-- 5. ASEGURADOS
--   Segmento actual: 55 % activos, 17 % pensionistas, 23 % derechohabientes, 5 % cesantes.
--   Cambios dentro del periodo (quedan en el historial):
--     JUBILACION     30 % de los pensionistas (antes eran activos)
--     CESE           todos los cesantes (antes eran activos)
--     CAMBIO_ENTIDAD 10 % de los activos (cambiaron de empleador)
------------------------------------------------------------
DECLARE @NomF TABLE (id INT PRIMARY KEY, n NVARCHAR(40));
INSERT INTO @NomF VALUES (0,N'María'),(1,N'Ana'),(2,N'Rosa'),(3,N'Carmen'),(4,N'Lucía'),
                         (5,N'Elena'),(6,N'Patricia'),(7,N'Sofía'),(8,N'Julia'),(9,N'Teresa');
DECLARE @NomM TABLE (id INT PRIMARY KEY, n NVARCHAR(40));
INSERT INTO @NomM VALUES (0,N'José'),(1,N'Luis'),(2,N'Carlos'),(3,N'Jorge'),(4,N'Miguel'),
                         (5,N'Pedro'),(6,N'Juan'),(7,N'Víctor'),(8,N'Raúl'),(9,N'Manuel');
DECLARE @Ape TABLE (id INT PRIMARY KEY, n NVARCHAR(40));
INSERT INTO @Ape VALUES (0,N'Quispe'),(1,N'Flores'),(2,N'Sánchez'),(3,N'Rodríguez'),(4,N'García'),
                        (5,N'Mamani'),(6,N'Huamán'),(7,N'Torres'),(8,N'Rojas'),(9,N'Vargas'),
                        (10,N'Chávez'),(11,N'Ramírez'),(12,N'Castillo'),(13,N'Mendoza'),(14,N'Díaz'),
                        (15,N'Espinoza'),(16,N'Gutiérrez'),(17,N'Ramos'),(18,N'Cruz'),(19,N'Salazar');

;WITH N AS
(
    SELECT n AS rn FROM #Tally WHERE n <= @NumAsegurados
),
R AS
(
    SELECT rn,
           (CHECKSUM(CONCAT(@Seed, '-SEG-',  rn)) & 2147483647) % 100              AS r_seg,
           (CHECKSUM(CONCAT(@Seed, '-CHG-',  rn)) & 2147483647) % 100              AS r_chg,
           (CHECKSUM(CONCAT(@Seed, '-ALTA-', rn)) & 2147483647)                    AS r_alta,
           (CHECKSUM(CONCAT(@Seed, '-FCHG-', rn)) & 2147483647) % (@NumMeses - 1)  AS r_fchg,
           (CHECKSUM(CONCAT(@Seed, '-ENT-',  rn)) & 2147483647) % @NumEntidades    AS r_ent,
           (CHECKSUM(CONCAT(@Seed, '-ENT2-', rn)) & 2147483647) % (@NumEntidades - 1) AS r_ent2,
           (CHECKSUM(CONCAT(@Seed, '-EDAD-', rn)) & 2147483647)                    AS r_edad,
           (CHECKSUM(CONCAT(@Seed, '-SEXO-', rn)) & 2147483647) % 2                AS r_sexo,
           (CHECKSUM(CONCAT(@Seed, '-NOM-',  rn)) & 2147483647) % 10               AS r_nom,
           (CHECKSUM(CONCAT(@Seed, '-AP1-',  rn)) & 2147483647) % 20               AS r_ap1,
           (CHECKSUM(CONCAT(@Seed, '-AP2-',  rn)) & 2147483647) % 20               AS r_ap2
    FROM N
),
S AS
(
    SELECT r.*,
           CASE WHEN r_seg < 55 THEN 'TITULAR_ACTIVO'
                WHEN r_seg < 72 THEN 'TITULAR_PENSIONISTA'
                WHEN r_seg < 95 THEN 'DERECHOHABIENTE'
                ELSE 'CESANTE' END AS seg_actual
    FROM R r
),
C AS
(
    SELECT s.*,
           CASE WHEN seg_actual = 'CESANTE'                          THEN 'CESE'
                WHEN seg_actual = 'TITULAR_PENSIONISTA' AND r_chg < 30 THEN 'JUBILACION'
                WHEN seg_actual = 'TITULAR_ACTIVO'      AND r_chg < 10 THEN 'CAMBIO_ENTIDAD'
                ELSE 'NINGUNO' END AS tipo_cambio
    FROM S s
)
SELECT c.rn,
       CONCAT('AS', RIGHT('000000' + CAST(c.rn AS VARCHAR(6)), 6))          AS codigo,
       CAST(40000000 + c.rn * 37 AS VARCHAR(15))                            AS documento,
       CONCAT(a1.n, N' ', a2.n, N', ', COALESCE(nf.n, nm.n))                AS nombres,
       CASE WHEN c.r_sexo = 0 THEN 'F' ELSE 'M' END                         AS sexo,
       c.seg_actual,
       c.tipo_cambio,
       -- quien cambia de condición ya estaba dado de alta antes del periodo
       CASE WHEN c.tipo_cambio <> 'NINGUNO'
            THEN DATEADD(DAY, c.r_alta % 4500, CAST('2012-01-01' AS DATE))
            ELSE DATEADD(DAY, c.r_alta % 5000, CAST('2012-01-01' AS DATE)) END AS fecha_alta,
       CASE WHEN c.tipo_cambio <> 'NINGUNO'
            THEN DATEADD(MONTH, 1 + c.r_fchg, @Desde) END                   AS fecha_cambio,
       1 + c.r_ent                                                          AS ent_ant_rn,
       CASE WHEN c.tipo_cambio = 'CAMBIO_ENTIDAD'
            THEN 1 + (c.r_ent + 1 + c.r_ent2) % @NumEntidades
            ELSE 1 + c.r_ent END                                            AS ent_act_rn,
       DATEADD(DAY,
               -((CASE c.seg_actual
                      WHEN 'TITULAR_PENSIONISTA' THEN 62 + c.r_edad % 27
                      WHEN 'DERECHOHABIENTE'     THEN c.r_edad % 76
                      ELSE 23 + c.r_edad % 38 END) * 365 + (c.r_edad / 97) % 365),
               CAST('2026-06-30' AS DATE))                                  AS fecha_nacimiento
INTO #AseGen
FROM C c
JOIN @Ape a1 ON a1.id = c.r_ap1
JOIN @Ape a2 ON a2.id = c.r_ap2
LEFT JOIN @NomF nf ON nf.id = c.r_nom AND c.r_sexo = 0
LEFT JOIN @NomM nm ON nm.id = c.r_nom AND c.r_sexo = 1;

-- El alta no puede ser anterior al nacimiento (ni antes de los 18 años para un titular)
UPDATE #AseGen
SET fecha_alta = CASE
        WHEN seg_actual = 'DERECHOHABIENTE' AND fecha_alta < fecha_nacimiento THEN fecha_nacimiento
        WHEN seg_actual <> 'DERECHOHABIENTE' AND fecha_alta < DATEADD(YEAR, 18, fecha_nacimiento)
             THEN DATEADD(YEAR, 18, fecha_nacimiento)
        ELSE fecha_alta END;

INSERT INTO asegurados (codigo, documento, nombres, fecha_nacimiento, sexo, fecha_alta, estado, id_segmento, id_entidad)
SELECT g.codigo, g.documento, g.nombres, g.fecha_nacimiento, g.sexo, g.fecha_alta, 'ACTIVO',
       s.id_segmento,
       CASE WHEN g.seg_actual = 'TITULAR_ACTIVO' THEN e.id_entidad END
FROM #AseGen g
JOIN segmentos s ON s.descripcion = g.seg_actual
LEFT JOIN #EntMap e ON e.rn = g.ent_act_rn;

SELECT g.*, a.id_asegurado
INTO #Ase
FROM #AseGen g
JOIN asegurados a ON a.codigo = g.codigo;

------------------------------------------------------------
-- 6. HISTORIAL DE CONDICIÓN (tramos de segmento + empleador)
------------------------------------------------------------
INSERT INTO asegurados_condicion_hist (id_asegurado, id_segmento, id_entidad, fecha_desde, fecha_hasta)
-- tramo anterior al cambio: era titular activo con su empleador anterior
SELECT a.id_asegurado, s.id_segmento, e.id_entidad, a.fecha_alta, DATEADD(DAY, -1, a.fecha_cambio)
FROM #Ase a
JOIN segmentos s ON s.descripcion = N'TITULAR_ACTIVO'
JOIN #EntMap e ON e.rn = a.ent_ant_rn
WHERE a.tipo_cambio <> 'NINGUNO'
UNION ALL
-- tramo vigente (igual a lo que dice hoy la tabla asegurados)
SELECT a.id_asegurado, s.id_segmento,
       CASE WHEN a.seg_actual = 'TITULAR_ACTIVO' THEN e.id_entidad END,
       CASE WHEN a.tipo_cambio <> 'NINGUNO' THEN a.fecha_cambio ELSE a.fecha_alta END,
       NULL
FROM #Ase a
JOIN segmentos s ON s.descripcion = a.seg_actual
LEFT JOIN #EntMap e ON e.rn = a.ent_act_rn;

------------------------------------------------------------
-- 7. AFILIACIONES
------------------------------------------------------------
-- 7.1 Plan básico para todos desde su alta. El cesante conserva la
--     cobertura 6 meses después del cese (latencia) y luego se da de baja.
INSERT INTO afiliaciones (id_asegurado, id_cobertura, fecha_afiliacion, fecha_baja, estado)
SELECT a.id_asegurado, c.id_cobertura, a.fecha_alta, fb.fecha_baja,
       CASE WHEN fb.fecha_baja IS NULL THEN 'VIGENTE' ELSE 'BAJA' END
FROM #Ase a
JOIN coberturas c ON c.codigo = 'BAS-01'
CROSS APPLY (SELECT CASE WHEN a.tipo_cambio = 'CESE'
                          AND DATEADD(DAY, -1, DATEADD(MONTH, 6, a.fecha_cambio)) <= @DatosHasta
                         THEN DATEADD(DAY, -1, DATEADD(MONTH, 6, a.fecha_cambio)) END AS fecha_baja) fb;

-- 7.2 Coberturas adicionales (0 a 3, distintas entre sí). Los cesantes no toman adicionales.
;WITH Cant AS
(
    SELECT a.id_asegurado, a.rn, a.fecha_alta,
           CASE WHEN x.r % 100 < 35 THEN 0
                WHEN x.r % 100 < 75 THEN 1
                WHEN x.r % 100 < 93 THEN 2
                ELSE 3 END AS k
    FROM #Ase a
    CROSS APPLY (SELECT CHECKSUM(CONCAT(@Seed, '-NCOMP-', a.rn)) & 2147483647 AS r) x
    WHERE a.seg_actual <> 'CESANTE'
),
Opciones AS
(
    SELECT ca.id_asegurado, ca.rn, ca.fecha_alta, ca.k, c.id_cobertura, c.codigo,
           ROW_NUMBER() OVER (PARTITION BY ca.id_asegurado
                              ORDER BY CAST(CHECKSUM(CONCAT(@Seed, '-PICK-', ca.rn, '-', c.codigo)) & 2147483647 AS BIGINT)
                                       + CASE WHEN c.codigo LIKE 'ESP%' THEN 1500000000 ELSE 0 END) AS orden
    FROM Cant ca
    CROSS JOIN coberturas c
    WHERE c.codigo <> 'BAS-01' AND ca.k > 0
),
Elegidas AS
(
    SELECT o.id_asegurado, o.id_cobertura,
           DATEADD(DAY,
                   CASE WHEN DATEDIFF(DAY, o.fecha_alta, @UltimaAfiliacion) <= 0 THEN 0
                        ELSE (CHECKSUM(CONCAT(@Seed, '-FAFI-', o.rn, '-', o.codigo)) & 2147483647)
                             % DATEDIFF(DAY, o.fecha_alta, @UltimaAfiliacion) END,
                   o.fecha_alta) AS fecha_afiliacion,
           CHECKSUM(CONCAT(@Seed, '-BAJA-', o.rn, '-', o.codigo)) & 2147483647 AS r_baja
    FROM Opciones o
    WHERE o.orden <= o.k
)
INSERT INTO afiliaciones (id_asegurado, id_cobertura, fecha_afiliacion, fecha_baja, estado)
SELECT e.id_asegurado, e.id_cobertura, e.fecha_afiliacion, fb.fecha_baja,
       CASE WHEN fb.fecha_baja IS NULL THEN 'VIGENTE' ELSE 'BAJA' END
FROM Elegidas e
CROSS APPLY (SELECT CASE WHEN e.r_baja % 100 < 12
                          AND DATEADD(DAY, 30 + e.r_baja % 700, e.fecha_afiliacion) <= @DatosHasta
                         THEN DATEADD(DAY, 30 + e.r_baja % 700, e.fecha_afiliacion) END AS fecha_baja) fb;

-- Contexto de cada afiliación y su ventana activa dentro del periodo de datos
SELECT af.id_afiliacion, af.id_asegurado, a.rn, a.seg_actual,
       c.codigo AS cob_codigo, cat.nombre AS categoria, c.aporte_referencial,
       af.fecha_afiliacion, af.fecha_baja,
       CASE WHEN af.fecha_afiliacion > @Desde THEN af.fecha_afiliacion ELSE @Desde END AS win_ini,
       CASE WHEN af.fecha_baja IS NOT NULL AND af.fecha_baja < @DatosHasta THEN af.fecha_baja ELSE @DatosHasta END AS win_fin
INTO #Afi
FROM afiliaciones af
JOIN #Ase a                   ON a.id_asegurado = af.id_asegurado
JOIN coberturas c             ON c.id_cobertura = af.id_cobertura
JOIN categorias_cobertura cat ON cat.id_categoria = c.id_categoria;

------------------------------------------------------------
-- 8. CARGAS (una por mes y tabla, al día siguiente del cierre)
------------------------------------------------------------
DECLARE @Destinos TABLE (tabla_destino VARCHAR(30), sistema_origen VARCHAR(30), hora INT);
INSERT INTO @Destinos
VALUES ('operaciones', 'SIS_ATENCIONES',    2),
       ('costos',      'SIS_LIQUIDACIONES', 3),
       ('ingresos',    'SIS_RECAUDACION',   4);

INSERT INTO cargas (sistema_origen, tabla_destino, periodo_desde, periodo_hasta, fecha_inicio, estado)
SELECT d.sistema_origen, d.tabla_destino, m.mes_ini, m.mes_fin,
       DATEADD(HOUR, d.hora, CAST(DATEADD(DAY, 1, m.mes_fin) AS DATETIME2(0))), 'COMPLETADA'
FROM #Meses m
CROSS JOIN @Destinos d;

-- Padrón de condiciones (historial) cargado al cierre
INSERT INTO cargas (sistema_origen, tabla_destino, periodo_desde, periodo_hasta, fecha_inicio, estado)
VALUES ('SIS_PADRON', 'asegurados_condicion_hist', '2012-01-01', @DatosHasta,
        DATEADD(HOUR, 1, CAST(DATEADD(DAY, 1, @DatosHasta) AS DATETIME2(0))), 'COMPLETADA');

-- Ejemplo de carga fallida: recaudación de junio 2025 falló y se reintentó una hora después
INSERT INTO cargas (sistema_origen, tabla_destino, periodo_desde, periodo_hasta, fecha_inicio, fecha_fin,
                    filas_leidas, filas_cargadas, filas_rechazadas, estado)
VALUES ('SIS_RECAUDACION', 'ingresos', '2025-06-01', '2025-06-30',
        '2025-07-01T03:00:00', '2025-07-01T03:02:00', 3120, 0, 3120, 'FALLIDA');

SELECT tabla_destino, periodo_desde AS mes_ini, id_carga
INTO #CargaMes
FROM cargas
WHERE estado = 'COMPLETADA' AND tabla_destino IN ('operaciones', 'ingresos', 'costos');

------------------------------------------------------------
-- 9. OPERACIONES (una fila por atención)
--    Uso mensual esperado según segmento y tipo de cobertura; se escala
--    para llegar a @TargetOperaciones.
------------------------------------------------------------
SELECT f.id_afiliacion, f.seg_actual, f.cob_codigo, f.categoria, f.win_ini,
       DATEDIFF(DAY, f.win_ini, f.win_fin) + 1 AS dias,
       (DATEDIFF(DAY, f.win_ini, f.win_fin) + 1) / 30.0
       * CASE WHEN f.categoria = N'BASICA'
              THEN CASE f.seg_actual WHEN 'TITULAR_ACTIVO'      THEN 0.8
                                     WHEN 'TITULAR_PENSIONISTA' THEN 2.0
                                     WHEN 'DERECHOHABIENTE'     THEN 1.0
                                     ELSE 0.7 END
              WHEN f.categoria = N'COMPLEMENTARIA' THEN 0.25
              ELSE 0.08 END
       * (0.4 + ((CHECKSUM(CONCAT(@Seed, '-USO-', f.rn, '-', f.cob_codigo)) & 2147483647) % 121) / 100.0) AS oper_raw
INTO #OpCtx
FROM #Afi f
WHERE f.win_fin >= f.win_ini;

DECLARE @SumRaw FLOAT = (SELECT SUM(oper_raw) FROM #OpCtx);
DECLARE @Escala FLOAT = CASE WHEN @SumRaw > 0 THEN @TargetOperaciones / @SumRaw ELSE 1 END;

;WITH Exp AS
(
    SELECT o.id_afiliacion, o.seg_actual, o.cob_codigo, o.categoria, o.win_ini, o.dias, t.n AS occ
    FROM #OpCtx o
    JOIN #Tally t ON t.n <= CAST(ROUND(o.oper_raw * @Escala, 0) AS INT)
),
R AS
(
    SELECT e.*,
           CHECKSUM(CONCAT(@Seed, '-OPF-', e.id_afiliacion, '-', e.occ)) & 2147483647        AS r_f,
           (CHECKSUM(CONCAT(@Seed, '-OPT-', e.id_afiliacion, '-', e.occ)) & 2147483647) % 100 AS r_t,
           (CHECKSUM(CONCAT(@Seed, '-OPC-', e.id_afiliacion, '-', e.occ)) & 2147483647) % 100 AS r_c,
           CHECKSUM(CONCAT(@Seed, '-OPI-', e.id_afiliacion, '-', e.occ)) & 2147483647        AS r_i,
           (CHECKSUM(CONCAT(@Seed, '-OPE-', e.id_afiliacion, '-', e.occ)) & 2147483647) % 100 AS r_e
    FROM Exp e
),
T AS
(
    SELECT r.*,
           DATEADD(DAY, r.r_f % r.dias, r.win_ini) AS fecha,
           CASE
               WHEN r.categoria = N'BASICA' THEN
                    CASE WHEN r.r_t < 70 THEN 'ATENCION_MEDICA'
                         WHEN r.r_t < 82 THEN 'REFERENCIA'
                         WHEN r.r_t < 90 THEN 'CARTA_GARANTIA'
                         ELSE 'SOLICITUD_REEMBOLSO' END
               WHEN r.categoria = N'COMPLEMENTARIA' THEN
                    CASE WHEN r.r_t < 75 THEN 'ATENCION_MEDICA' ELSE 'SOLICITUD_REEMBOLSO' END
               ELSE CASE WHEN r.r_t < 40 THEN 'CARTA_GARANTIA'
                         WHEN r.r_t < 75 THEN 'REFERENCIA'
                         ELSE 'ATENCION_MEDICA' END
           END AS tipo_operacion
    FROM R r
),
K AS
(
    SELECT t.*,
           CASE
               WHEN t.tipo_operacion IN ('REFERENCIA', 'CARTA_GARANTIA') THEN 'IPRESS_REFERENCIA'
               WHEN t.tipo_operacion = 'SOLICITUD_REEMBOLSO'              THEN 'IPRESS_RED'
               WHEN t.cob_codigo = 'COM-03'                               THEN 'DOMICILIO'
               WHEN t.seg_actual = 'TITULAR_PENSIONISTA' THEN
                    CASE WHEN t.r_c < 45 THEN 'IPRESS_RED'
                         WHEN t.r_c < 65 THEN 'TELEMEDICINA'
                         WHEN t.r_c < 80 THEN 'FARMACIA_CONVENIO'
                         ELSE 'DOMICILIO' END
               ELSE CASE WHEN t.r_c < 55 THEN 'IPRESS_RED'
                         WHEN t.r_c < 80 THEN 'TELEMEDICINA'
                         WHEN t.r_c < 95 THEN 'FARMACIA_CONVENIO'
                         ELSE 'DOMICILIO' END
           END AS canal
    FROM T t
)
SELECT CONCAT('AT', RIGHT('000000000' + CAST(ROW_NUMBER() OVER (ORDER BY k.fecha, k.id_afiliacion, k.occ) AS VARCHAR(9)), 9)) AS codigo_origen,
       k.id_afiliacion, k.categoria, k.fecha, k.tipo_operacion, k.canal,
       CAST(ROUND(
            CASE k.tipo_operacion
                WHEN 'ATENCION_MEDICA' THEN
                     CASE k.canal WHEN 'TELEMEDICINA'      THEN 30 + k.r_i % 70
                                  WHEN 'FARMACIA_CONVENIO' THEN 20 + k.r_i % 180
                                  ELSE 60 + k.r_i % 340 END
                WHEN 'REFERENCIA'      THEN 400  + k.r_i % 2600
                WHEN 'CARTA_GARANTIA'  THEN 1500 + k.r_i % 13500
                ELSE 80 + k.r_i % 1100 END
            * CASE WHEN k.categoria = N'ESPECIAL' THEN 1.8 ELSE 1.0 END
            + (k.r_i % 100) / 100.0, 2) AS DECIMAL(12,2)) AS importe_bruto,
       CASE WHEN k.r_e < 86 THEN 'LIQUIDADA'
            WHEN k.r_e < 93 THEN 'OBSERVADA'
            ELSE 'RECHAZADA' END AS estado
INTO #OpGen
FROM K k;

INSERT INTO operaciones (codigo_origen, id_carga, id_afiliacion, id_canal, id_periodo, tipo_operacion, importe_bruto, estado)
SELECT g.codigo_origen, cm.id_carga, g.id_afiliacion, ca.id_canal, p.id_periodo, g.tipo_operacion, g.importe_bruto, g.estado
FROM #OpGen g
JOIN canales ca  ON ca.nombre = g.canal
JOIN periodos p  ON p.fecha = g.fecha
JOIN #CargaMes cm ON cm.tabla_destino = 'operaciones'
                 AND cm.mes_ini = DATEFROMPARTS(YEAR(g.fecha), MONTH(g.fecha), 1);

SELECT g.*, o.id_operacion
INTO #Op
FROM #OpGen g
JOIN operaciones o ON o.codigo_origen = g.codigo_origen;

------------------------------------------------------------
-- 10. COSTOS
--   Una liquidación por atención no rechazada (5 a 44 días después).
--   Reembolsos: además un costo de procesamiento.
--   Administrativo: prorrateo trimestral sobre cada afiliación básica activa.
------------------------------------------------------------
CREATE TABLE #CostoGen
(
    codigo        VARCHAR(40)   NOT NULL,
    id_afiliacion BIGINT        NOT NULL,
    id_operacion  BIGINT        NULL,
    fecha_liq     DATE          NOT NULL,
    tipo_costo    VARCHAR(30)   NOT NULL,
    importe       DECIMAL(12,2) NOT NULL
);

;WITH L AS
(
    SELECT o.*, x.r,
           CASE WHEN DATEADD(DAY, 5 + x.r % 40, o.fecha) > @DatosHasta THEN @DatosHasta
                ELSE DATEADD(DAY, 5 + x.r % 40, o.fecha) END AS fecha_liq
    FROM #Op o
    CROSS APPLY (SELECT CHECKSUM(CONCAT(@Seed, '-LQ-', o.codigo_origen)) & 2147483647 AS r) x
    WHERE o.estado <> 'RECHAZADA'
)
INSERT INTO #CostoGen (codigo, id_afiliacion, id_operacion, fecha_liq, tipo_costo, importe)
SELECT CONCAT('LQ', SUBSTRING(l.codigo_origen, 3, 9)), l.id_afiliacion, l.id_operacion, l.fecha_liq,
       CASE WHEN l.tipo_operacion IN ('REFERENCIA', 'CARTA_GARANTIA') THEN 'REFERENCIA_INTERINSTITUCIONAL'
            ELSE 'PRESTACION' END,
       CAST(ROUND(l.importe_bruto * CASE WHEN l.estado = 'LIQUIDADA' THEN 0.80 + (l.r % 21) / 100.0
                                         ELSE 0.45 + (l.r % 31) / 100.0 END, 2) AS DECIMAL(12,2))
FROM L l
UNION ALL
SELECT CONCAT('PR', SUBSTRING(l.codigo_origen, 3, 9)), l.id_afiliacion, l.id_operacion, l.fecha_liq,
       'PROCESAMIENTO_REEMBOLSO', CAST(12 + (l.r % 1300) / 100.0 AS DECIMAL(12,2))
FROM L l
WHERE l.tipo_operacion = 'SOLICITUD_REEMBOLSO';

INSERT INTO #CostoGen (codigo, id_afiliacion, id_operacion, fecha_liq, tipo_costo, importe)
SELECT CONCAT('AD', CONVERT(CHAR(8), q.fecha, 112), '-', f.id_afiliacion), f.id_afiliacion, NULL, q.fecha,
       'ADMINISTRATIVO',
       CAST(9 + ((CHECKSUM(CONCAT(@Seed, '-ADM-', f.id_afiliacion, '-', q.fecha)) & 2147483647) % 600) / 100.0 AS DECIMAL(12,2))
FROM #Afi f
JOIN periodos q ON q.mes IN (3, 6, 9, 12)
               AND q.fecha = EOMONTH(q.fecha)
               AND q.fecha BETWEEN @Desde AND @DatosHasta
WHERE f.categoria = N'BASICA'
  AND f.fecha_afiliacion <= q.fecha
  AND (f.fecha_baja IS NULL OR f.fecha_baja >= q.fecha);

INSERT INTO costos (codigo_origen, id_carga, id_afiliacion, id_periodo, id_operacion, tipo_costo, importe)
SELECT g.codigo, cm.id_carga, g.id_afiliacion, p.id_periodo, g.id_operacion, g.tipo_costo, g.importe
FROM #CostoGen g
JOIN periodos p   ON p.fecha = g.fecha_liq
JOIN #CargaMes cm ON cm.tabla_destino = 'costos'
                 AND cm.mes_ini = DATEFROMPARTS(YEAR(g.fecha_liq), MONTH(g.fecha_liq), 1);

------------------------------------------------------------
-- 11. INGRESOS
--   Aportes mensuales según la condición del asegurado EN ESE MES
--   (tomada del historial), devengados el día 1 del mes:
--     básica + activo       -> APORTE_ENTIDAD (paga su empleador de ese mes)
--     básica + pensionista  -> APORTE_TITULAR (retención) + TRANSFERENCIA_TESORO
--     básica + derechohab./cesante -> sin aporte (los financia el sistema)
--     adicional (no cesante) -> APORTE_TITULAR
--   ~3 % de meses sin pago (morosidad).
--   Recuperación por subrogación: ~3 % de atenciones liquidadas.
------------------------------------------------------------
CREATE TABLE #IngGen
(
    codigo        VARCHAR(40)   NOT NULL,
    id_afiliacion BIGINT        NOT NULL,
    fecha         DATE          NOT NULL,
    id_entidad    INT           NULL,
    id_operacion  BIGINT        NULL,
    tipo          VARCHAR(30)   NOT NULL,
    importe       DECIMAL(12,2) NOT NULL
);

;WITH Base AS
(
    SELECT f.id_afiliacion, f.categoria, f.aporte_referencial, m.mes_ini,
           s.descripcion AS seg_mes, h.id_entidad,
           CHECKSUM(CONCAT(@Seed, '-AP-', f.id_afiliacion, '-', m.mes_ini)) & 2147483647 AS r
    FROM #Afi f
    JOIN #Meses m ON f.fecha_afiliacion <= m.mes_ini
                 AND (f.fecha_baja IS NULL OR f.fecha_baja >= m.mes_ini)
    JOIN asegurados_condicion_hist h ON h.id_asegurado = f.id_asegurado
                                    AND m.mes_ini >= h.fecha_desde
                                    AND (h.fecha_hasta IS NULL OR m.mes_ini <= h.fecha_hasta)
    JOIN segmentos s ON s.id_segmento = h.id_segmento
)
INSERT INTO #IngGen (codigo, id_afiliacion, fecha, id_entidad, id_operacion, tipo, importe)
SELECT CONCAT('RC', CONVERT(CHAR(6), b.mes_ini, 112), '-', b.id_afiliacion, '-', v.sufijo),
       b.id_afiliacion, b.mes_ini, v.id_entidad, NULL, v.tipo, v.importe
FROM Base b
CROSS APPLY
(
    SELECT 'E' AS sufijo, 'APORTE_ENTIDAD' AS tipo, b.id_entidad AS id_entidad,
           CAST(ROUND(b.aporte_referencial * (0.75 + (b.r % 71) / 100.0), 2) AS DECIMAL(12,2)) AS importe
    WHERE b.categoria = N'BASICA' AND b.seg_mes = N'TITULAR_ACTIVO'
    UNION ALL
    SELECT 'T', 'APORTE_TITULAR', NULL,
           CAST(ROUND(b.aporte_referencial * 0.40 * (0.90 + (b.r % 21) / 100.0), 2) AS DECIMAL(12,2))
    WHERE b.categoria = N'BASICA' AND b.seg_mes = N'TITULAR_PENSIONISTA'
    UNION ALL
    SELECT 'S', 'TRANSFERENCIA_TESORO', NULL,
           CAST(ROUND(b.aporte_referencial * 0.30, 2) AS DECIMAL(12,2))
    WHERE b.categoria = N'BASICA' AND b.seg_mes = N'TITULAR_PENSIONISTA'
    UNION ALL
    SELECT 'T', 'APORTE_TITULAR', NULL,
           CAST(ROUND(b.aporte_referencial * (0.95 + (b.r % 11) / 100.0), 2) AS DECIMAL(12,2))
    WHERE b.categoria <> N'BASICA' AND b.seg_mes <> N'CESANTE'
) v
WHERE b.r % 100 >= 3;

INSERT INTO #IngGen (codigo, id_afiliacion, fecha, id_entidad, id_operacion, tipo, importe)
SELECT CONCAT('SB', SUBSTRING(o.codigo_origen, 3, 9)), o.id_afiliacion,
       CASE WHEN DATEADD(DAY, 30 + x.r % 90, o.fecha) > @DatosHasta THEN @DatosHasta
            ELSE DATEADD(DAY, 30 + x.r % 90, o.fecha) END,
       NULL, o.id_operacion, 'RECUPERACION_SUBROGACION',
       CAST(ROUND(o.importe_bruto * (0.50 + (x.r % 41) / 100.0), 2) AS DECIMAL(12,2))
FROM #Op o
CROSS APPLY (SELECT CHECKSUM(CONCAT(@Seed, '-SUB-', o.codigo_origen)) & 2147483647 AS r) x
WHERE o.estado = 'LIQUIDADA'
  AND o.tipo_operacion IN ('ATENCION_MEDICA', 'REFERENCIA', 'CARTA_GARANTIA')
  AND x.r % 100 < 3;

INSERT INTO ingresos (codigo_origen, id_carga, id_afiliacion, id_periodo, id_entidad_pagadora, id_operacion, tipo_ingreso, importe)
SELECT g.codigo, cm.id_carga, g.id_afiliacion, p.id_periodo, g.id_entidad, g.id_operacion, g.tipo, g.importe
FROM #IngGen g
JOIN periodos p   ON p.fecha = g.fecha
JOIN #CargaMes cm ON cm.tabla_destino = 'ingresos'
                 AND cm.mes_ini = DATEFROMPARTS(YEAR(g.fecha), MONTH(g.fecha), 1);

------------------------------------------------------------
-- 12. AJUSTES FINALES
------------------------------------------------------------
-- Asegurado sin ninguna afiliación abierta -> INACTIVO
UPDATE a
SET estado = 'INACTIVO'
FROM asegurados a
WHERE NOT EXISTS (SELECT 1 FROM afiliaciones af
                  WHERE af.id_asegurado = a.id_asegurado AND af.fecha_baja IS NULL);

-- Métricas de cada carga completada
UPDATE c
SET filas_cargadas   = x.filas,
    filas_rechazadas = y.rech,
    filas_leidas     = x.filas + y.rech,
    fecha_fin        = DATEADD(SECOND, 90 + x.filas / 20, c.fecha_inicio)
FROM cargas c
CROSS APPLY (SELECT CASE c.tabla_destino
                        WHEN 'operaciones' THEN (SELECT COUNT(*) FROM operaciones o WHERE o.id_carga = c.id_carga)
                        WHEN 'ingresos'    THEN (SELECT COUNT(*) FROM ingresos i    WHERE i.id_carga = c.id_carga)
                        WHEN 'costos'      THEN (SELECT COUNT(*) FROM costos k      WHERE k.id_carga = c.id_carga)
                        ELSE (SELECT COUNT(*) FROM asegurados_condicion_hist) END AS filas) x
CROSS APPLY (SELECT CASE WHEN c.tabla_destino = 'asegurados_condicion_hist' THEN 0
                         ELSE (CHECKSUM(CONCAT(@Seed, '-RECH-', c.id_carga)) & 2147483647) % 12 END AS rech) y
WHERE c.estado = 'COMPLETADA';

COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH;

------------------------------------------------------------
-- 13. VALIDACIONES Y REPORTES DE EJEMPLO
------------------------------------------------------------

-- 13.1 Conteo por tabla
SELECT 'segmentos' AS tabla, COUNT(*) AS filas FROM segmentos
UNION ALL SELECT 'categorias_cobertura', COUNT(*) FROM categorias_cobertura
UNION ALL SELECT 'coberturas', COUNT(*) FROM coberturas
UNION ALL SELECT 'canales', COUNT(*) FROM canales
UNION ALL SELECT 'periodos', COUNT(*) FROM periodos
UNION ALL SELECT 'entidades_empleadoras', COUNT(*) FROM entidades_empleadoras
UNION ALL SELECT 'asegurados', COUNT(*) FROM asegurados
UNION ALL SELECT 'asegurados_condicion_hist', COUNT(*) FROM asegurados_condicion_hist
UNION ALL SELECT 'afiliaciones', COUNT(*) FROM afiliaciones
UNION ALL SELECT 'cargas', COUNT(*) FROM cargas
UNION ALL SELECT 'operaciones', COUNT(*) FROM operaciones
UNION ALL SELECT 'ingresos', COUNT(*) FROM ingresos
UNION ALL SELECT 'costos', COUNT(*) FROM costos;

-- 13.2 Consistencia: todo movimiento debe tener segmento histórico (esperado: 0)
SELECT COUNT(*) AS movimientos_sin_segmento_historico
FROM vw_resultado_financiero
WHERE id_segmento IS NULL;

-- 13.3 Consistencia: atenciones no rechazadas sin costo (esperado: 0)
SELECT COUNT(*) AS atenciones_sin_costo
FROM operaciones o
WHERE o.estado <> 'RECHAZADA'
  AND NOT EXISTS (SELECT 1 FROM costos c WHERE c.id_operacion = o.id_operacion);

-- 13.4 Asegurados por segmento actual y cuántos cambiaron de condición
SELECT s.descripcion AS segmento_actual,
       COUNT(*) AS asegurados,
       SUM(CASE WHEN h.tramos > 1 THEN 1 ELSE 0 END) AS con_cambio_en_el_periodo
FROM asegurados a
JOIN segmentos s ON s.id_segmento = a.id_segmento
CROSS APPLY (SELECT COUNT(*) AS tramos FROM asegurados_condicion_hist x WHERE x.id_asegurado = a.id_asegurado) h
GROUP BY s.descripcion
ORDER BY asegurados DESC;

-- 13.5 Resultado por segmento: histórico vs actual (muestra para qué sirve el historial)
SELECT s.descripcion AS segmento,
       SUM(CASE WHEN r.id_segmento = s.id_segmento THEN r.resultado_financiero ELSE 0 END) AS resultado_segmento_historico,
       SUM(CASE WHEN a.id_segmento = s.id_segmento THEN r.resultado_financiero ELSE 0 END) AS resultado_segmento_actual
FROM segmentos s
CROSS JOIN vw_resultado_financiero r
JOIN asegurados a ON a.id_asegurado = r.id_asegurado
GROUP BY s.descripcion
ORDER BY s.descripcion;

-- 13.6 Resultado mensual por segmento (vista del modelo)
SELECT anio, mes, segmento, asegurados, total_ingreso, total_costo, resultado_financiero
FROM vw_resultado_por_segmento_mensual
ORDER BY anio, mes, segmento;

-- 13.7 Ingresos por tipo
SELECT tipo_ingreso, COUNT(*) AS movimientos, SUM(importe) AS importe
FROM ingresos
GROUP BY tipo_ingreso
ORDER BY importe DESC;

-- 13.8 Costos por canal de atención (el administrativo no tiene canal)
SELECT COALESCE(ca.nombre, N'(administrativo)') AS canal,
       COUNT(*) AS costos, SUM(c.importe) AS importe
FROM costos c
LEFT JOIN operaciones o ON o.id_operacion = c.id_operacion
LEFT JOIN canales ca    ON ca.id_canal = o.id_canal
GROUP BY ca.nombre
ORDER BY importe DESC;

-- 13.9 Resultado por cobertura
SELECT cb.codigo, cb.nombre,
       SUM(x.ingreso) AS ingresos, SUM(x.costo) AS costos, SUM(x.ingreso) - SUM(x.costo) AS resultado
FROM (SELECT id_afiliacion, importe AS ingreso, 0 AS costo FROM ingresos
      UNION ALL
      SELECT id_afiliacion, 0, importe FROM costos) x
JOIN afiliaciones af ON af.id_afiliacion = x.id_afiliacion
JOIN coberturas cb   ON cb.id_cobertura = af.id_cobertura
GROUP BY cb.codigo, cb.nombre
ORDER BY cb.codigo;

-- 13.10 Top 10 entidades por aportes pagados
SELECT TOP 10 e.codigo, e.nombre_entidad, COUNT(*) AS aportes, SUM(i.importe) AS importe
FROM ingresos i
JOIN entidades_empleadoras e ON e.id_entidad = i.id_entidad_pagadora
GROUP BY e.codigo, e.nombre_entidad
ORDER BY importe DESC;

-- 13.11 Control de cargas
SELECT tabla_destino, estado, COUNT(*) AS cargas,
       SUM(filas_cargadas) AS filas_cargadas, SUM(filas_rechazadas) AS filas_rechazadas
FROM cargas
GROUP BY tabla_destino, estado
ORDER BY tabla_destino, estado;

-- 13.12 Top 10 asegurados con peor resultado acumulado
SELECT TOP 10 r.codigo_asegurado, s.descripcion AS segmento_actual,
       SUM(r.total_ingreso) AS ingresos, SUM(r.total_costo) AS costos,
       SUM(r.resultado_financiero) AS resultado
FROM vw_resultado_financiero r
JOIN asegurados a ON a.id_asegurado = r.id_asegurado
JOIN segmentos s  ON s.id_segmento = a.id_segmento
GROUP BY r.codigo_asegurado, s.descripcion
ORDER BY resultado ASC;

------------------------------------------------------------
-- 14. LIMPIEZA DE TEMPORALES
------------------------------------------------------------
DROP TABLE IF EXISTS #Tally, #Meses, #EntMap, #AseGen, #Ase, #Afi, #CargaMes,
                     #OpCtx, #OpGen, #Op, #CostoGen, #IngGen;

-- FIN
