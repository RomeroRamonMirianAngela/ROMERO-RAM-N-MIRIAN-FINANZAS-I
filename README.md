# Política monetaria de la Reserva Federal y bonos soberanos peruanos

**Universidad Nacional del Centro del Perú (UNCP)**  
**Facultad:** Economía  
**Curso:** Finanzas I  
**Unidad:** I  
**Tema:** 37 - Política monetaria de la Reserva Federal y bonos soberanos peruanos  
**Estudiante:** ROMERO RAMÓN MIRIAN ANGELA  
**Código de matrícula:** 2024200523C  
**Periodo de análisis:** 2010-01-01 a 2025-12-31  
**Fecha de extracción:** 2026-09-24

## 1. Descripción del proyecto

Este repositorio contiene un flujo reproducible para extraer, limpiar, integrar y analizar series financieras diarias provenientes del Banco Central de Reserva del Perú (BCRP) y de Federal Reserve Economic Data (FRED).

La pregunta de investigación es:

> ¿En qué medida la política monetaria de la Reserva Federal y las condiciones financieras externas se relacionan con el rendimiento del bono soberano peruano a 10 años durante 2010-2025?

La llave común utilizada para integrar las fuentes es **`fecha`**. No se utiliza un identificador numérico artificial porque cada observación de la base final corresponde a una fecha única.

### Vía de extracción utilizada en la Unidad I

El proyecto corresponde a la **Unidad I** y utiliza una vía automatizada de extracción mediante **API**. La segunda vía de extracción es opcional para esta unidad, por lo que no se incorpora un archivo `02_scraping_web.py`. Las dos instituciones utilizadas, BCRP y FRED, se consultan programáticamente desde `01_extraccion_api.py`.

## 2. Fuentes de datos y endpoints

| Fuente | Serie | Código | Unidad original | Uso en el estudio |
|---|---|---|---|---|
| BCRPData | Rendimiento del bono soberano peruano a 10 años en soles | `PD31893DD` | Porcentaje | Variable dependiente |
| BCRPData | EMBIG Perú | `PD04709XD` | Puntos básicos | Riesgo país |
| FRED | Effective Federal Funds Rate | `DFF` | Porcentaje | Política monetaria de la Fed |
| FRED | Market Yield on U.S. Treasury Securities at 2-Year Constant Maturity | `DGS2` | Porcentaje | Condiciones financieras externas |
| FRED | Market Yield on U.S. Treasury Securities at 10-Year Constant Maturity | `DGS10` | Porcentaje | Condiciones financieras externas |

### BCRPData

Endpoint base:

```text
https://estadisticas.bcrp.gob.pe/estadisticas/series/api
```

Patrón utilizado:

```text
https://estadisticas.bcrp.gob.pe/estadisticas/series/api/[codigo]/csv/[fecha_inicio]/[fecha_fin]/[idioma]
```

Parámetros congelados en el script:

```text
FECHA_INICIO = 2010-01-01
FECHA_CORTE  = 2025-12-31
IDIOMA       = esp
```

### FRED

Endpoint utilizado:

```text
https://api.stlouisfed.org/fred/series/observations
```

El script consulta las series `DFF`, `DGS2` y `DGS10` con el mismo periodo congelado. FRED requiere una clave personal que se lee desde la variable de entorno `FRED_API_KEY`; la clave real no se escribe dentro del código ni se versiona en Git.

## 3. Obtención y configuración de la clave API de FRED

Para reproducir la extracción de FRED, cada usuario debe utilizar su propia clave API.

1. Ingresar a la documentación oficial de claves de FRED:
   `https://fred.stlouisfed.org/docs/api/api_key.html`
2. Crear una cuenta de FRED o iniciar sesión con una cuenta existente.
3. Solicitar o visualizar una clave API personal desde la cuenta de FRED.
4. En la raíz del proyecto, crear el archivo `.env` tomando como plantilla `.env.example`.
5. Registrar la clave con el siguiente formato:

```text
FRED_API_KEY=TU_CLAVE_PERSONAL
```

El archivo `.env.example` entregado en el repositorio debe contener únicamente:

```text
FRED_API_KEY=
```


## 4. Estructura del repositorio

```text
ROMERO-RAM-N-MIRIAN-FINANZAS-I/
├── codigo/
│   ├── 01_extraccion_api.py
│   ├── 03_limpieza_datos.py
│   └── 04_analisis.R
├── datos_crudos/
│   ├── datos_crudos_bcrp_bono_10a_2024200523C.csv
│   ├── datos_crudos_bcrp_embig_2024200523C.csv
│   ├── datos_crudos_fred_DFF_2024200523C.csv
│   ├── datos_crudos_fred_DGS2_2024200523C.csv
│   └── datos_crudos_fred_DGS10_2024200523C.csv
├── datos_procesados/
│   ├── datos_procesados_2024200523C.csv
│   ├── diagnostico_limpieza_2024200523C.csv
│   └── tratamiento_atipicos_2024200523C.csv
├── salidas/
├── .env.example
├── .gitattributes
├── .gitignore
├── .here
├── log_ejecucion.txt
└── README.md
```

Los archivos de `datos_crudos/` se conservan como evidencia primaria y no se editan manualmente.

## 5. Orden de ejecución

El proyecto debe ejecutarse desde la raíz del repositorio en el siguiente orden:

```text
01_extraccion_api.py -> 03_limpieza_datos.py -> 04_analisis.R
```

### 5.1 Extracción por API

```bash
python codigo/01_extraccion_api.py
```

El script:

- consulta programáticamente las series del BCRP y FRED;
- utiliza `FECHA_INICIO` y `FECHA_CORTE` como parámetros fijos;
- maneja errores y reintentos de conexión;
- registra los códigos de respuesta HTTP en `log_ejecucion.txt`;
- guarda los archivos crudos en `datos_crudos/`.

### 5.2 Limpieza e integración

```bash
python codigo/03_limpieza_datos.py
```

El script realiza:

- tipificación de fechas y variables numéricas;
- integración de las fuentes mediante la llave común `fecha`;
- construcción de un calendario de días hábiles;
- diagnóstico de valores faltantes;
- conservación únicamente de observaciones completas, sin imputación;
- diagnóstico de posibles valores atípicos mediante rango intercuartílico (IQR);
- conversión del EMBIG de puntos básicos a puntos porcentuales;
- winsorización de las variables peruanas seleccionadas para controlar valores extremos sin eliminar observaciones;
- validación de fechas únicas y ordenadas;
- generación de la base procesada y de los archivos de diagnóstico.

La base procesada final contiene **3,838 observaciones**, desde `2010-01-04` hasta `2025-12-31`. En el calendario común se descartaron 336 filas incompletas. Después de trabajar con observaciones completas, la winsorización modificó 35 observaciones del bono peruano y 86 observaciones del EMBIG Perú.

### 5.3 Análisis estadístico y econométrico

En Windows / Git Bash:

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" --vanilla codigo/04_analisis.R > prueba_ejecucion.txt 2>&1
```

Una ejecución correcta devuelve código de salida `0`.

El archivo `codigo/04_analisis.R` utiliza exclusivamente la base procesada y genera las tablas y figuras del análisis en `salidas/`.

## 6. Base procesada

Archivo principal:

```text
datos_procesados/datos_procesados_2024200523C.csv
```

La base final contiene **9 columnas**, de las cuales 8 son variables sustantivas o transformaciones analíticas y 1 corresponde a la fecha de observación:

| Variable | Descripción | Unidad |
|---|---|---|
| `fecha` | Fecha de la observación y llave común de integración | Fecha |
| `bono_pe_10a_soles` | Rendimiento original del bono soberano peruano a 10 años | % |
| `bono_pe_10a_soles_w` | Rendimiento del bono peruano tratado mediante winsorización IQR | % |
| `embig_peru_pbs` | EMBIG Perú original | Puntos básicos |
| `embig_peru_pp` | EMBIG Perú convertido a puntos porcentuales | p.p. |
| `embig_peru_pp_w` | EMBIG Perú en puntos porcentuales tratado mediante winsorización IQR | p.p. |
| `tasa_fondos_federales` | Tasa efectiva de fondos federales | % |
| `tesoro_2a` | Rendimiento del Tesoro de EE. UU. a 2 años | % |
| `tesoro_10a` | Rendimiento del Tesoro de EE. UU. a 10 años | % |

La definición completa, frecuencia, fuente exacta y endpoint de cada variable se documenta adicionalmente en `diccionario_variables`.

## 7. Análisis generado desde la base procesada

El análisis final incluye:

- estadísticos descriptivos, incluido el coeficiente de variación;
- series de tiempo;
- boxplots de las variables finales;
- matriz y gráfico de correlaciones de Pearson;
- gráfico conjunto de dispersión para las cuatro variables explicativas;
- pruebas de estacionariedad ADF y KPSS;
- correlaciones parciales con ajuste de Holm;
- estimación por MCO;
- diagnóstico de multicolinealidad mediante VIF;
- reparametrización mediante el spread entre el Tesoro de EE. UU. a 2 años y Fed funds;
- pruebas de Breusch-Pagan y Breusch-Godfrey;
- prueba de normalidad de Jarque-Bera;
- inferencia robusta con errores estándar Newey-West (HAC);
- regresión móvil de 252 observaciones para el coeficiente de Fed funds;
- importancia relativa mediante el método LMG.

En la regresión móvil se evaluaron 718 ventanas: 714 fueron estimables y 4 se conservaron como no estimables (`NA`) para mantener trazabilidad sin detener la ejecución.

Tanto BCRP como FRED participan en las tablas y figuras del análisis; ninguna fuente se utiliza de manera decorativa.

## 8. Entorno y versiones de software

### Python

- Python 3.14.7
- pandas 3.0.5
- numpy 2.5.3
- requests 2.34.2
- python-dotenv 1.2.3

### R

- R 4.5.1 (2025-06-13 ucrt)
- here 1.0.2
- readr 2.1.5
- dplyr 1.1.4
- tidyr 1.3.1
- purrr 1.2.0
- tibble 3.3.0
- ggplot2 4.0.1
- corrplot 0.95
- ppcor 1.1
- lmtest 0.9-40
- sandwich 3.1-1
- car 3.1-3
- tseries 0.10-58
- relaimpo 2.2-7

La información adicional del entorno de R se conserva en:

```text
salidas/sessionInfo_R.txt
```

## 9. Integridad de la base procesada

SHA-256 del archivo entregado `datos_procesados_2024200523C.csv`:

```text
4a05b888904d3b1b1627c1747dc1f78d59840c5d6ce64c0d97146b367077f0ac
```

Este hash corresponde al archivo procesado entregado y permite comprobar que no fue modificado posteriormente.

Para recalcularlo desde Git Bash:

```bash
sha256sum datos_procesados/datos_procesados_2024200523C.csv
```

Las fuentes financieras son fuentes vivas y pueden revisar observaciones históricas. Por ello, una extracción futura legítima puede producir diferencias respecto del archivo entregado. El hash anterior debe cotejarse contra **el archivo procesado entregado**, no contra una descarga futura.

## 10. Reproducibilidad

Para reproducir el flujo:

1. Clonar el repositorio.
2. Instalar las dependencias de Python y R indicadas en este README y en los archivos de documentación del entorno.
3. Crear `.env` a partir de `.env.example` e ingresar una clave propia de FRED.
4. Ejecutar `01_extraccion_api.py`.
5. Ejecutar `03_limpieza_datos.py`.
6. Ejecutar `04_analisis.R`.
7. Revisar `log_ejecucion.txt`, `datos_procesados/` y `salidas/`.

No se utilizan rutas absolutas del equipo dentro de los scripts; las rutas del proyecto son relativas. Los datos no se descargan manualmente desde el navegador ni se editan en Excel.

## 11. Archivos de documentación de la entrega

Además de los scripts, datos y salidas, la entrega debe conservar los siguientes elementos en el proyecto:

- `README.md`: descripción y procedimiento de reproducción;
- `diccionario_variables.xlsx` o `diccionario_variables.md`: nombre, definición, unidad, frecuencia, fuente y endpoint de cada variable;
- `requirements.txt` o `sessionInfo.txt`: versiones exactas del entorno utilizado;
- `.env.example`: plantilla de la variable `FRED_API_KEY`, sin incluir la clave personal;
- `log_ejecucion.txt`: fecha y hora de las extracciones, número de filas y códigos HTTP;
- `incidencias_fuente.md`: solo si hubiera existido un bloqueo técnico y una sustitución autorizada.

En este proyecto no se utilizó una fuente sustituta ni se reportó un bloqueo técnico que requiera `incidencias_fuente.md`.

## 12. Repositorio GitHub

Repositorio oficial del proyecto:

```text
https://github.com/RomeroRamonMirianAngela/ROMERO-RAM-N-MIRIAN-FINANZAS-I.git
```

El historial del repositorio debe conservar como mínimo tres commits realizados en fechas distintas para documentar el proceso de trabajo.

## 13. Resumen de cumplimiento técnico

- Unidad I: una vía automatizada mediante API; segunda vía opcional.
- Periodo congelado mediante `FECHA_INICIO` y `FECHA_CORTE`.
- Más de 1,000 observaciones y más de 5 años de frecuencia diaria.
- Base procesada con 9 columnas y más de 4 variables sustantivas.
- Integración por la llave común `fecha`.
- Datos crudos conservados sin edición manual.
- Tratamiento reproducible de faltantes y valores atípicos en `03_limpieza_datos.py`.
- Tablas y figuras regeneradas desde `04_analisis.R`.
- Clave de FRED gestionada mediante variable de entorno.
- SHA-256 declarado para el archivo procesado entregado.
- Repositorio GitHub documentado.
