# Diccionario de variables

**Estudiante:** ROMERO RAMÓN MIRIAN ANGELA  
**Código de matrícula:** 2024200523C  
**Curso:** Finanzas I  
**Tema 37:** Política monetaria de la Reserva Federal y bonos soberanos peruanos  
**Fecha de extracción:** 2026-09-24  
**Periodo de estudio:** 2010-01-01 a 2025-12-31  
**Frecuencia:** diaria, armonizada a días hábiles  
**Llave común de integración:** `fecha`

## Base procesada

Archivo principal: `datos_procesados/datos_procesados_2024200523C.csv`

La base final contiene 9 columnas. Las fuentes BCRP y FRED se integran mediante la variable `fecha`. Las transformaciones y el tratamiento de valores atípicos se realizan en `codigo/03_limpieza_datos.py`.

| Variable | Definición | Unidad de medida | Frecuencia | Fuente exacta | Serie / código | URL o endpoint de origen | Tratamiento en la base procesada |
|---|---|---|---|---|---|---|---|
| `fecha` | Fecha correspondiente a cada observación de las series integradas. Funciona como llave común para unir las fuentes. | Fecha (`AAAA-MM-DD`) | Diaria, días hábiles | Elaboración propia a partir de las fechas de BCRP y FRED | No aplica | No aplica | Convertida a tipo fecha, ordenada de forma ascendente y validada como única. |
| `bono_pe_10a_soles` | Rendimiento del bono soberano peruano a 10 años denominado en soles. | Porcentaje (%) | Diaria | Banco Central de Reserva del Perú (BCRPData) | `PD31893DD` | `https://estadisticas.bcrp.gob.pe/estadisticas/series/api` | Variable original normalizada a formato numérico; se conserva para trazabilidad. |
| `bono_pe_10a_soles_w` | Rendimiento del bono soberano peruano a 10 años luego del tratamiento de valores atípicos. | Porcentaje (%) | Diaria | Derivada de BCRP `PD31893DD` | Variable derivada | Derivada de `bono_pe_10a_soles` | Winsorización mediante criterio IQR en `03_limpieza_datos.py`; no se eliminan observaciones por ser atípicas. |
| `embig_peru_pbs` | EMBIG Perú, indicador del riesgo país respecto de bonos del Tesoro de EE. UU. | Puntos básicos (pbs) | Diaria | Banco Central de Reserva del Perú (BCRPData) | `PD04709XD` | `https://estadisticas.bcrp.gob.pe/estadisticas/series/api` | Variable original normalizada a formato numérico; se conserva para trazabilidad. |
| `embig_peru_pp` | EMBIG Perú expresado en puntos porcentuales. | Puntos porcentuales (p.p.) | Diaria | Derivada de BCRP `PD04709XD` | Variable derivada | Derivada de `embig_peru_pbs` | Conversión de puntos básicos a puntos porcentuales: `embig_peru_pbs / 100`. |
| `embig_peru_pp_w` | EMBIG Perú en puntos porcentuales luego del tratamiento de valores atípicos. | Puntos porcentuales (p.p.) | Diaria | Derivada de BCRP `PD04709XD` | Variable derivada | Derivada de `embig_peru_pp` | Winsorización mediante criterio IQR en `03_limpieza_datos.py`. |
| `tasa_fondos_federales` | Tasa efectiva de fondos federales de Estados Unidos. | Porcentaje (%) | Diaria | Federal Reserve Economic Data (FRED), Federal Reserve Bank of St. Louis | `DFF` | `https://api.stlouisfed.org/fred/series/observations` | Convertida a formato numérico y armonizada con el calendario común; sin winsorización. |
| `tesoro_2a` | Rendimiento del bono del Tesoro de Estados Unidos con vencimiento constante a 2 años. | Porcentaje (%) | Diaria | Federal Reserve Economic Data (FRED), Federal Reserve Bank of St. Louis | `DGS2` | `https://api.stlouisfed.org/fred/series/observations` | Convertida a formato numérico y armonizada con el calendario común; sin winsorización. |
| `tesoro_10a` | Rendimiento del bono del Tesoro de Estados Unidos con vencimiento constante a 10 años. | Porcentaje (%) | Diaria | Federal Reserve Economic Data (FRED), Federal Reserve Bank of St. Louis | `DGS10` | `https://api.stlouisfed.org/fred/series/observations` | Convertida a formato numérico y armonizada con el calendario común; sin winsorización. |

## Notas de construcción y limpieza

- Los datos crudos se conservan sin edición manual en la carpeta `datos_crudos/`.
- Las series se tipifican y se unen por la llave común `fecha`.
- Se conserva únicamente el conjunto de días con información completa en todas las series, sin imputación de valores faltantes.
- El diagnóstico de valores atípicos se realiza con el criterio de rango intercuartílico (IQR).
- El tratamiento de atípicos se aplica únicamente a `bono_pe_10a_soles` y `embig_peru_pp`, generando las versiones `bono_pe_10a_soles_w` y `embig_peru_pp_w`.
- Las variables originales se mantienen en la base procesada para facilitar la trazabilidad y el cotejo con las fuentes oficiales.
