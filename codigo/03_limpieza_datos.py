# =============================================================================
# DATOS DE IDENTIFICACIÓN DEL TRABAJO
# =============================================================================
# Nombres y Apellidos completos: ROMERO RAMÓN MIRIAN ANGELA
# Código de matrícula: 2024200523C
# Tema y número del temario:
# Tema 37 - Política monetaria de la Reserva Federal y bonos soberanos peruanos
# Fecha de extracción: 2026-09-24
# =============================================================================

"""
03_limpieza_datos.py
--------------------
VARIABLES DE LA BASE FINAL
==========================

1. bono_pe_10a_soles
   Rendimiento del bono soberano peruano a 10 años.
   Fuente: BCRP.
   Código: PD31893DD.

2. embig_peru_pbs
   EMBIG Perú o riesgo país, expresado en puntos básicos.
   Fuente: BCRP.
   Código: PD04709XD.

3. tasa_fondos_federales
   Tasa efectiva de fondos federales de Estados Unidos.
   Fuente: FRED.
   Código: DFF.

4. tesoro_2a
   Rendimiento del Treasury de Estados Unidos a 2 años.
   Fuente: FRED.
   Código: DGS2.

5. tesoro_10a
   Rendimiento del Treasury de Estados Unidos a 10 años.
   Fuente: FRED.
   Código: DGS10.


CRITERIOS DE LIMPIEZA
=====================

El procedimiento sigue estos criterios:

1. Verificar que todos los archivos crudos existan y no estén vacíos.

2. Corregir únicamente problemas de formato de los CSV del BCRP
   (por ejemplo, <br>, entidades HTML o problemas de codificación),
   sin alterar el valor económico de las observaciones.

3. Convertir todas las fechas a un tipo de fecha real de pandas.

4. Convertir los valores económicos a formato numérico.

5. Interpretar expresiones de ausencia de dato como:
       "n.d."
       "."
       cadena vacía
   como valores faltantes NaN.

6. Construir un calendario común de lunes a viernes entre:
       2010-01-01
       2025-12-31

7. Unir todas las series usando la fecha como llave común.

8. Identificar datos faltantes y posibles valores atípicos mediante el
   rango intercuartílico (IQR).

9. Los posibles valores atípicos NO se eliminan automáticamente.
   En variables financieras, valores extremos pueden representar episodios
   económicos reales y no necesariamente errores.

10. No se imputan ni inventan valores faltantes.

11. Para construir la base econométrica completa se conservan únicamente
    las fechas en las que existen datos para las cinco variables.

12. Antes de guardar la base se realizan validaciones de consistencia:
    ausencia de duplicados, orden cronológico, ausencia de NaN en la base
    final y fechas dentro del periodo oficial.

13. Se genera un hash SHA-256 del archivo final. Este valor funciona como
    una huella digital del archivo y permite comprobar su integridad.
"""

import os
import re
import html
import hashlib
import logging
from io import StringIO

import numpy as np
import pandas as pd



# =============================================================================
# PASO 1. DEFINIR LOS PARÁMETROS DEL PROYECTO
# =============================================================================

CODIGO_MATRICULA = "2024200523C"
FECHA_INICIO = "2010-01-01"
FECHA_CORTE = "2025-12-31"

# Series de FRED y nombre final de cada variable.
SERIES_FRED = {
    "DFF": "tasa_fondos_federales",
    "DGS2": "tesoro_2a",
    "DGS10": "tesoro_10a",
}

# Variables esperadas en la base final, en orden.
COLUMNAS_FINALES = [
    "bono_pe_10a_soles",
    "embig_peru_pbs",
    "tasa_fondos_federales",
    "tesoro_2a",
    "tesoro_10a",
]


# =============================================================================
# PASO 2. CONSTRUIR LAS RUTAS DE ENTRADA Y SALIDA
# =============================================================================

# Este script vive en /codigo; la raíz del proyecto está un nivel arriba.
RUTA_BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RUTA_CRUDOS = os.path.join(RUTA_BASE, "datos_crudos")
RUTA_PROCESADOS = os.path.join(RUTA_BASE, "datos_procesados")
os.makedirs(RUTA_PROCESADOS, exist_ok=True)

# Archivos crudos del BCRP generados por 01_extraccion_api.py.
RUTA_BONO = os.path.join(
    RUTA_CRUDOS,
    f"datos_crudos_bcrp_bono_10a_{CODIGO_MATRICULA}.csv",
)

RUTA_EMBIG = os.path.join(
    RUTA_CRUDOS,
    f"datos_crudos_bcrp_embig_{CODIGO_MATRICULA}.csv",
)


def ruta_fred(codigo_serie):
    """Devuelve la ruta del CSV crudo de una serie de FRED."""
    return os.path.join(
        RUTA_CRUDOS,
        f"datos_crudos_fred_{codigo_serie}_{CODIGO_MATRICULA}.csv",
    )


# Archivos de salida.
RUTA_SALIDA = os.path.join(
    RUTA_PROCESADOS,
    f"datos_procesados_{CODIGO_MATRICULA}.csv",
)

RUTA_DIAGNOSTICO = os.path.join(
    RUTA_PROCESADOS,
    f"diagnostico_limpieza_{CODIGO_MATRICULA}.csv",
)

# Archivo de registro compartido con 01_extraccion_api.py.
RUTA_LOG = os.path.join(RUTA_BASE, "log_ejecucion.txt")


# =============================================================================
# PASO 3. CONFIGURAR EL REGISTRO DE EJECUCIÓN (LOG)
# =============================================================================

logging.basicConfig(
    filename=RUTA_LOG,
    filemode="a",
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    encoding="utf-8",
)

logger = logging.getLogger("limpieza_datos")


# =============================================================================
# PASO 4. VALIDAR LOS ARCHIVOS DE ENTRADA
# =============================================================================


# Esta función realiza una validación previa muy sencilla pero importante, comprobando:
#
# 1. que realmente exista en la ruta esperada;
# 2. que su tamaño sea mayor que cero.
#
# Si cualquiera de estas condiciones falla, el programa se detiene.
# Esto evita continuar con una base incompleta y descubrir el problema
# solamente al final del proceso.

def verificar_archivo(ruta, etiqueta):
    """Verifica que un archivo de entrada exista y no esté vacío."""
    if not os.path.isfile(ruta):
        raise FileNotFoundError(
            f"No se encontró el archivo de {etiqueta}:\n{ruta}\n"
            "Ejecuta primero 01_extraccion_api.py."
        )

    if os.path.getsize(ruta) == 0:
        raise ValueError(f"El archivo de {etiqueta} está vacío: {ruta}")


# =============================================================================
# PASO 5. CORREGIR EL FORMATO TEXTUAL DE LOS CSV DEL BCRP
# =============================================================================
#
# El objetivo es transformar el archivo a una forma que pandas pueda leer
# correctamente, conservando las observaciones originales.

def corregir_formato_texto_bcrp(bytes_crudos):
    """
    Corrige peculiaridades de formato de la respuesta CSV de BCRPData sin
    modificar los valores económicos:

    1. Convierte <br>, <br/> o <br /> en saltos de línea reales.
    2. Intenta corregir mojibake si existe.
    3. Convierte entidades HTML en caracteres normales.
    """

    texto = bytes_crudos.decode("utf-8", errors="replace")

    # El BCRP puede usar etiquetas <br> en lugar de saltos de línea reales.
    texto = re.sub(r"<br\s*/?>", "\n", texto, flags=re.IGNORECASE)

    # Corrige una posible doble codificación solo cuando es posible hacerlo
    # de manera reversible.
    try:
        texto_corregido = texto.encode("latin-1").decode("utf-8")
        texto = texto_corregido
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass

    # Convierte entidades HTML: &ntilde; -> ñ, &amp; -> &, etc.
    texto = html.unescape(texto)

    return texto.strip() + "\n"


# =============================================================================
# PASO 6. NORMALIZAR LAS FECHAS DEL BCRP
# =============================================================================

MESES = {
    "ene": 1,
    "feb": 2,
    "mar": 3,
    "abr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "ago": 8,
    "set": 9,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dic": 12,
}



def normalizar_periodo(texto_periodo):
    """
    Convierte fechas del BCRP a pandas.Timestamp.

    Acepta, entre otros:
    - 02Ene10
    - 02.Ene.10
    - 02-Ene-2010
    - 02 Ene 2010
    - Ene.2020

    Si no reconoce el formato, devuelve pd.NaT.
    """

    if pd.isna(texto_periodo):
        return pd.NaT

    texto = str(texto_periodo).strip()

    patron = (
        r"^\s*"
        r"(?:(\d{1,2})[.\-\s]?)?"
        r"([A-Za-zÁÉÍÓÚáéíóúÑñ]{3})"
        r"[.\-\s]?"
        r"(\d{2,4})"
        r"\s*$"
    )

    coincidencia = re.match(patron, texto)

    if not coincidencia:
        return pd.NaT

    dia, mes, anio = coincidencia.groups()
    mes = mes.lower()

    if mes not in MESES:
        return pd.NaT

    anio = int(anio)

    # Para este proyecto, los años de dos dígitos pertenecen al siglo XXI.
    if anio < 100:
        anio += 2000

    try:
        return pd.Timestamp(
            year=anio,
            month=MESES[mes],
            day=int(dia or 1),
        )
    except ValueError:
        return pd.NaT


# =============================================================================
# PASO 7. LEER Y TIPIFICAR LOS DATOS CRUDOS DEL BCRP
# =============================================================================


# Esta función realiza el proceso completo de lectura de UNA serie del BCRP.
#
# Secuencia:
#
# 1. verifica el archivo;
# 2. lo abre en modo binario;
# 3. corrige su formato textual;
# 4. lo convierte a DataFrame;
# 5. normaliza la fecha;
# 6. convierte el valor económico a número;
# 7. convierte "n.d." y otros textos de ausencia a NaN;
# 8. elimina fechas inválidas;
# 9. ordena cronológicamente;
# 10. elimina fechas duplicadas conservando la última observación;
# 11. restringe la serie al periodo oficial del estudio.


def leer_bcrp_crudo(ruta_csv, nombre_columna):
    """
    Lee un CSV crudo del BCRP con una sola serie.

    Devuelve únicamente:
        fecha
        <nombre_columna>
    """

    verificar_archivo(ruta_csv, nombre_columna)

    with open(ruta_csv, "rb") as archivo:
        bytes_crudos = archivo.read()

    texto_corregido = corregir_formato_texto_bcrp(bytes_crudos)

    try:
        df = pd.read_csv(
            StringIO(texto_corregido),
            sep=",",
            dtype=str,
        )
    except pd.errors.ParserError as error:
        raise ValueError(
            f"No se pudo interpretar el CSV del BCRP: "
            f"{os.path.basename(ruta_csv)}"
        ) from error

    # El archivo debe contener periodo + una sola serie.
    if df.shape[1] != 2:
        raise ValueError(
            f"Se esperaban 2 columnas en {os.path.basename(ruta_csv)}, "
            f"pero se encontraron {df.shape[1]}. "
            f"Columnas detectadas: {list(df.columns)}"
        )

    df.columns = ["periodo", nombre_columna]

    # Elimina filas completamente vacías que eventualmente pudiera traer el archivo.
    df = df.dropna(how="all")

    # Convierte periodo a fecha.
    df["fecha"] = df["periodo"].apply(normalizar_periodo)

    n_sin_fecha = int(df["fecha"].isna().sum())

    if n_sin_fecha:
        logger.warning(
            f"{nombre_columna}: {n_sin_fecha} filas con fecha "
            "no reconocida (se descartan)"
        )

    # Limpieza mínima de valores.
    # Se conserva la regla: cualquier texto no numérico pasa a NaN.
    valores = (
        df[nombre_columna]
        .astype("string")
        .str.strip()
        .replace({
            "": pd.NA,
            "n.d.": pd.NA,
            "n.d": pd.NA,
            "N.D.": pd.NA,
            "N.D": pd.NA,
            ".": pd.NA,
        })
    )

    # Si apareciera coma decimal, se normaliza únicamente cuando no hay punto.
    # Esto hace la lectura más robusta sin afectar números ya escritos con punto.
    mascara_coma_decimal = valores.str.contains(",", na=False) & ~valores.str.contains(
        r"\.", regex=True, na=False
    )
    valores.loc[mascara_coma_decimal] = valores.loc[mascara_coma_decimal].str.replace(
        ",", ".", regex=False
    )

    df[nombre_columna] = pd.to_numeric(valores, errors="coerce")

    # Descarta fechas inválidas, ordena y elimina duplicados de fecha.
    df = df.dropna(subset=["fecha"])
    df = df.sort_values("fecha")
    df = df.drop_duplicates(subset="fecha", keep="last")

    # Restringe al periodo oficial del estudio.
    df = df[
        df["fecha"].between(
            pd.Timestamp(FECHA_INICIO),
            pd.Timestamp(FECHA_CORTE),
            inclusive="both",
        )
    ]

    logger.info(
        f"{nombre_columna}: {len(df)} filas leidas del crudo BCRP"
    )

    return df[["fecha", nombre_columna]].reset_index(drop=True)


# =============================================================================
# PASO 8. LEER Y TIPIFICAR LOS DATOS CRUDOS DE FRED
# =============================================================================

# Función auxiliar para hacer la lectura de FRED más robusta.
#
# Los nombres de columnas pueden variar ligeramente según el formato de
# descarga. Por ejemplo, la fecha puede llamarse "period_start_date",
# "date" u "observation_date".
#
# Esta función busca el primer nombre válido ignorando diferencias entre
# mayúsculas/minúsculas y espacios.


def _detectar_columna(columnas, candidatos):
    """Busca una columna ignorando mayúsculas/minúsculas y espacios."""
    mapa = {str(col).strip().lower(): col for col in columnas}

    for candidato in candidatos:
        if candidato.lower() in mapa:
            return mapa[candidato.lower()]

    return None



# Esta función lee UNA serie de FRED desde su CSV crudo.
#
# En los archivos utilizados en este proyecto, FRED suele proporcionar:
#
#   period_start_date
#   DFF / DGS2 / DGS10
#   realtime_start_date
#   realtime_end_date
#
# Para el análisis se necesitan únicamente:
#
#   - la fecha de la observación;
#   - el valor de la serie.
#
# Las columnas realtime_* no se utilizan porque describen la ventana de
# disponibilidad/revisión del dato, no una variable económica adicional.


def leer_fred_csv(ruta_csv, codigo_serie, nombre_columna):
    """
    Lee un CSV crudo de FRED.

    Soporta el CSV oficial de FRED generado con file_type="csv".
    En este formato, la fecha puede venir como "period_start_date"
    y la columna de valores puede llamarse igual que el código de la serie
    (por ejemplo, DFF, DGS2 o DGS10). También admite variantes como
    "date", "observation_date" y "value" para mayor compatibilidad.
    """

    verificar_archivo(ruta_csv, f"FRED {codigo_serie}")

    # utf-8-sig elimina automáticamente un posible BOM al inicio del archivo.
    try:
        df = pd.read_csv(
            ruta_csv,
            dtype=str,
            encoding="utf-8-sig",
        )
    except UnicodeDecodeError:
        # Respaldo por si el archivo viniera con otra codificación compatible.
        df = pd.read_csv(
            ruta_csv,
            dtype=str,
            encoding="latin-1",
        )
    except pd.errors.ParserError as error:
        raise ValueError(
            f"No se pudo interpretar el CSV de FRED {codigo_serie}: "
            f"{os.path.basename(ruta_csv)}"
        ) from error

    if df.empty:
        raise ValueError(
            f"El CSV de FRED {codigo_serie} no contiene observaciones."
        )

    # FRED puede usar distintos nombres según el formato de descarga.
    # En los CSV generados por file_type="csv" la fecha aparece como
    # "period_start_date" y el valor suele estar en una columna con el
    # código de la propia serie (DFF, DGS2 o DGS10).
    columna_fecha = _detectar_columna(
        df.columns,
        [
            "period_start_date",
            "date",
            "observation_date",
            "fecha",
        ],
    )

    columna_valor = _detectar_columna(
        df.columns,
        [
            codigo_serie,
            "value",
        ],
    )

    if columna_fecha is None:
        raise ValueError(
            f"No se encontró una columna de fecha en "
            f"{os.path.basename(ruta_csv)}. "
            f"Columnas disponibles: {list(df.columns)}"
        )

    if columna_valor is None:
        raise ValueError(
            f"No se encontró la columna de valores de {codigo_serie} en "
            f"{os.path.basename(ruta_csv)}. "
            f"Columnas disponibles: {list(df.columns)}"
        )

    serie = pd.DataFrame()

    serie["fecha"] = pd.to_datetime(
        df[columna_fecha].astype("string").str.strip(),
        errors="coerce",
    )

    valores = (
        df[columna_valor]
        .astype("string")
        .str.strip()
        .replace({
            "": pd.NA,
            ".": pd.NA,
            "nan": pd.NA,
            "NaN": pd.NA,
        })
    )

    serie[nombre_columna] = pd.to_numeric(
        valores,
        errors="coerce",
    )

    n_sin_fecha = int(serie["fecha"].isna().sum())

    if n_sin_fecha:
        logger.warning(
            f"{nombre_columna} ({codigo_serie}): "
            f"{n_sin_fecha} filas con fecha invalida (se descartan)"
        )

    serie = serie.dropna(subset=["fecha"])
    serie = serie.sort_values("fecha")
    serie = serie.drop_duplicates(subset="fecha", keep="last")

    # Restringe al mismo periodo usado durante la extracción.
    serie = serie[
        serie["fecha"].between(
            pd.Timestamp(FECHA_INICIO),
            pd.Timestamp(FECHA_CORTE),
            inclusive="both",
        )
    ]

    logger.info(
        f"{nombre_columna} ({codigo_serie}): "
        f"{len(serie)} filas leidas del crudo FRED"
    )

    return serie[["fecha", nombre_columna]].reset_index(drop=True)



# Esta función repite leer_fred_csv() para DFF, DGS2 y DGS10.
#
# Cada serie se lee por separado y después las tres se unen por fecha mediante
# pd.concat(..., join="outer").
#
# La unión externa permite conservar inicialmente todas las fechas disponibles
# en cualquiera de las tres series. Los faltantes se analizarán después y no
# se ocultan durante la lectura.

def leer_fred_crudo(series):
    """
    Lee los CSV crudos de FRED, uno por serie, y devuelve una única tabla con
    la columna fecha y una columna por variable.
    """

    partes = []

    for codigo, nombre in series.items():
        serie = leer_fred_csv(
            ruta_fred(codigo),
            codigo,
            nombre,
        )

        partes.append(
            serie.set_index("fecha")
        )

    if not partes:
        raise ValueError("No se definieron series de FRED para procesar.")

    # Unión externa entre las tres series de FRED.
    fred = pd.concat(partes, axis=1, join="outer")
    fred = fred.sort_index().reset_index()

    return fred


# =============================================================================
# PASO 9. CONSTRUIR EL CALENDARIO COMÚN Y UNIR LAS FUENTES
# =============================================================================

# - se excluyen sábados y domingos;
# - los feriados no se eliminan del calendario automáticamente;
# - si una fuente no publicó dato en un feriado, ese día aparece como NaN.
#
# Luego cada tabla se incorpora mediante un left merge usando "fecha" como
# llave común.
#
# validate="one_to_one" obliga a que exista como máximo una observación por
# fecha en cada tabla. Si hubiera duplicados inesperados, pandas genera error
# en lugar de hacer una unión ambigua.

def unir_en_calendario(tablas):
    """
    Construye el calendario de lunes a viernes entre FECHA_INICIO y FECHA_CORTE
    y une cada tabla mediante la llave común 'fecha'.

    Los días sin dato quedan como NaN explícitos.
    """

    calendario = pd.bdate_range(
        start=FECHA_INICIO,
        end=FECHA_CORTE,
    )

    base = pd.DataFrame({"fecha": calendario})

    for tabla in tablas:
        if "fecha" not in tabla.columns:
            raise ValueError("Todas las tablas deben contener la columna 'fecha'.")

        base = base.merge(
            tabla,
            on="fecha",
            how="left",
            validate="one_to_one",
        )

    return base


# =============================================================================
# PASO 10. DIAGNOSTICAR DATOS FALTANTES Y POSIBLES ATÍPICOS
# =============================================================================

# Para cada variable se calcula:
#
# - número de días hábiles del calendario;
# - número de días con dato;
# - número de días sin dato;
# - número de posibles valores atípicos;
# - límite inferior del criterio IQR;
# - límite superior del criterio IQR.
#
# Criterio IQR:
#
#   IQR = Q3 - Q1
#
#   límite inferior = Q1 - 1.5 * IQR
#   límite superior = Q3 + 1.5 * IQR
#
# Un valor fuera de esos límites se MARCA como posible atípico.
#
# IMPORTANTE:
# no se elimina automáticamente porque, en una serie financiera, un valor
# extremo puede ser consecuencia de una crisis, anuncio monetario, cambio de
# riesgo país u otro episodio económico real.

def diagnosticar(base, columnas):
    """
    Cuenta faltantes y detecta posibles valores atípicos mediante IQR.

    Los valores atípicos solamente se reportan; no se eliminan.
    """

    filas = []

    for columna in columnas:
        datos_validos = base[columna].dropna()

        if datos_validos.empty:
            limite_inf = np.nan
            limite_sup = np.nan
            n_atipicos = 0

        else:
            q1 = datos_validos.quantile(0.25)
            q3 = datos_validos.quantile(0.75)
            iqr = q3 - q1

            limite_inf = q1 - 1.5 * iqr
            limite_sup = q3 + 1.5 * iqr

            atipicos = (
                base[columna].notna()
                & (
                    (base[columna] < limite_inf)
                    | (base[columna] > limite_sup)
                )
            )

            n_atipicos = int(atipicos.sum())

        filas.append(
            {
                "variable": columna,
                "dias_habiles": len(base),
                "dias_con_dato": int(base[columna].notna().sum()),
                "dias_sin_dato": int(base[columna].isna().sum()),
                "posibles_atipicos": n_atipicos,
                "limite_inferior": (
                    round(float(limite_inf), 4)
                    if pd.notna(limite_inf)
                    else np.nan
                ),
                "limite_superior": (
                    round(float(limite_sup), 4)
                    if pd.notna(limite_sup)
                    else np.nan
                ),
            }
        )

    return pd.DataFrame(filas)


# =============================================================================
# PASO 11. CALCULAR EL HASH DE INTEGRIDAD SHA-256
# =============================================================================



# SHA-256 genera una huella digital del archivo final.
#
# Si el contenido del CSV cambia, aunque sea mínimamente, el hash resultante
# también cambia.
#
# Por ello puede utilizarse para demostrar que el archivo analizado es
# exactamente el mismo que el archivo generado durante la limpieza.
#
# El archivo se lee por bloques de 65 536 bytes para no cargarlo completamente
# en memoria si su tamaño fuera grande.

def calcular_sha256(ruta):
    """Calcula el hash SHA-256 de un archivo."""

    hash_obj = hashlib.sha256()

    with open(ruta, "rb") as archivo:
        for bloque in iter(lambda: archivo.read(65536), b""):
            hash_obj.update(bloque)

    return hash_obj.hexdigest()


# =============================================================================
# PASO 12. EJECUTAR TODO EL PROCEDIMIENTO DE LIMPIEZA
# =============================================================================

if __name__ == "__main__":

    logger.info("=== INICIO 03_limpieza_datos ===")
    logger.info(
        f"Parametros congelados: FECHA_INICIO={FECHA_INICIO} | "
        f"FECHA_CORTE={FECHA_CORTE}"
    )

    try:
        # ---------------------------------------------------------------------
        # 1. VERIFICAR ARCHIVOS DE ENTRADA
        #
        # Antes de procesar datos se comprueba que existan los cinco archivos:
        #
        # - bono soberano peruano a 10 años;
        # - EMBIG Perú;
        # - DFF;
        # - DGS2;
        # - DGS10.
        #
        # Esta comprobación evita generar una base parcial por accidente.
        # ---------------------------------------------------------------------

        verificar_archivo(RUTA_BONO, "bono soberano peruano a 10 años")
        verificar_archivo(RUTA_EMBIG, "EMBIG Perú")

        for codigo in SERIES_FRED:
            verificar_archivo(
                ruta_fred(codigo),
                f"FRED {codigo}",
            )

        # ---------------------------------------------------------------------
        # 2. LECTURA Y TIPIFICACIÓN DE LOS CRUDOS
        #
        # En este punto cada archivo se transforma en una tabla con:
        #
        # - una columna de fecha;
        # - una columna numérica con la variable económica.
        #
        # Todavía NO se eliminan los días que tienen valores faltantes.
        # ---------------------------------------------------------------------

        bono = leer_bcrp_crudo(
            RUTA_BONO,
            "bono_pe_10a_soles",
        )

        embig = leer_bcrp_crudo(
            RUTA_EMBIG,
            "embig_peru_pbs",
        )

        fred = leer_fred_crudo(
            SERIES_FRED
        )

        # ---------------------------------------------------------------------
        # 3. UNIÓN EN CALENDARIO DE DÍAS HÁBILES
        #
        # Se crea una única tabla temporal de lunes a viernes y se incorporan
        # las cinco variables utilizando la fecha como llave común.
        #
        # Esto permite comparar las fuentes en el mismo eje temporal.
        # ---------------------------------------------------------------------

        base = unir_en_calendario(
            [bono, embig, fred]
        )

        # Garantiza orden estable de columnas.
        columnas_valor = [
            columna
            for columna in COLUMNAS_FINALES
            if columna in base.columns
        ]

        faltantes_columnas = set(COLUMNAS_FINALES) - set(columnas_valor)

        if faltantes_columnas:
            raise ValueError(
                "Faltan variables esperadas después de unir las fuentes: "
                + ", ".join(sorted(faltantes_columnas))
            )

        base = base[["fecha"] + COLUMNAS_FINALES]
        columnas_valor = COLUMNAS_FINALES.copy()

        n_inicial = len(base)

        # ---------------------------------------------------------------------
        # 4. DIAGNÓSTICO ANTES DE ELIMINAR FILAS INCOMPLETAS
        #
        # El diagnóstico se hace ANTES de dropna para documentar cuántos datos
        # faltaban originalmente y cuántos valores fueron marcados como
        # posibles atípicos.
        #
        # Así se conserva evidencia del proceso de limpieza.
        # ---------------------------------------------------------------------

        diagnostico = diagnosticar(
            base,
            columnas_valor,
        )

        print("Diagnóstico de faltantes y posibles atípicos:")
        print(
            diagnostico.to_string(index=False)
        )

        for _, fila in diagnostico.iterrows():
            logger.info(
                f"{fila['variable']}: "
                f"{fila['dias_sin_dato']} dias sin dato | "
                f"{fila['posibles_atipicos']} posibles atipicos "
                "(marcados, no eliminados)"
            )

        diagnostico.to_csv(
            RUTA_DIAGNOSTICO,
            index=False,
            encoding="utf-8",
            lineterminator="\n",
        )

        # ---------------------------------------------------------------------
        # 5. BASE COMPLETA: SOLO OBSERVACIONES CON TODAS LAS SERIES
        #
        # Para el archivo final se exige que una fecha tenga dato en las cinco
        # variables al mismo tiempo.
        #
        # dropna(subset=columnas_valor) elimina únicamente las filas incompletas.
        #
        # No se realiza interpolación, promedio, forward-fill ni otra forma de
        # imputación. Por tanto, el script no inventa observaciones.
        # ---------------------------------------------------------------------

        base = (
            base
            .dropna(subset=columnas_valor)
            .reset_index(drop=True)
        )

        n_final = len(base)
        n_descartadas = n_inicial - n_final

        logger.info(
            f"Filas antes: {n_inicial} | "
            f"descartadas: {n_descartadas} | "
            f"finales: {n_final}"
        )

        # ---------------------------------------------------------------------
        # 6. VALIDACIONES DE CONSISTENCIA
        #
        # Antes de guardar se realizan controles que funcionan como pruebas
        # internas de calidad:
        #
        # - la base no puede estar vacía;
        # - cada fecha debe ser única;
        # - las fechas deben estar ordenadas;
        # - no debe quedar ningún NaN en las cinco variables;
        # - todas las fechas deben pertenecer al periodo definido;
        # - no deben existir sábados ni domingos.
        # ---------------------------------------------------------------------

        if base.empty:
            raise ValueError(
                "La base final quedó vacía después de eliminar filas "
                "con datos faltantes. Revisa los archivos crudos."
            )

        if not base["fecha"].is_unique:
            raise ValueError("Hay fechas duplicadas en la base final.")

        if not base["fecha"].is_monotonic_increasing:
            raise ValueError("Las fechas no están ordenadas de forma ascendente.")

        if base[columnas_valor].isna().any().any():
            raise ValueError("Quedaron valores vacíos en la base final.")

        if not base["fecha"].between(
            pd.Timestamp(FECHA_INICIO),
            pd.Timestamp(FECHA_CORTE),
            inclusive="both",
        ).all():
            raise ValueError("Hay fechas fuera del periodo oficial del estudio.")

        # El calendario final debe contener únicamente lunes a viernes.
        if (base["fecha"].dt.dayofweek > 4).any():
            raise ValueError("La base final contiene fines de semana.")

        if n_final < 1000:
            logger.warning(
                f"La base tiene {n_final} observaciones "
                "(menos del minimo de 1000)."
            )

        # ---------------------------------------------------------------------
        # 7. GUARDADO DE LA BASE PROCESADA
        #
        # La fecha se convierte al formato ISO YYYY-MM-DD.
        #
        # Este formato facilita la importación posterior en R y evita
        # ambigüedades entre día/mes y mes/día.
        #
        # lineterminator="\\n" ayuda a producir un archivo más estable entre
        # Windows, macOS y Linux.
        # ---------------------------------------------------------------------

        # Se guarda la fecha como YYYY-MM-DD para un formato estable y simple
        # de importar en R.
        base_salida = base.copy()
        base_salida["fecha"] = base_salida["fecha"].dt.strftime("%Y-%m-%d")

        base_salida.to_csv(
            RUTA_SALIDA,
            index=False,
            encoding="utf-8",
            lineterminator="\n",
        )

        hash_sha256 = calcular_sha256(
            RUTA_SALIDA
        )

        logger.info(
            "Base procesada guardada en: "
            f"datos_procesados/{os.path.basename(RUTA_SALIDA)}"
        )

        logger.info(
            f"SHA-256 de {os.path.basename(RUTA_SALIDA)}: "
            f"{hash_sha256}"
        )

        # ---------------------------------------------------------------------
        # 8. RESUMEN EN PANTALLA
        #
        # Al finalizar se muestra:
        #
        # - filas iniciales;
        # - filas descartadas;
        # - filas finales;
        # - rango temporal;
        # - ubicación de los archivos generados;
        # - hash SHA-256;
        # - primeras y últimas observaciones;
        # - estadísticos descriptivos básicos.
        #
        # Este resumen permite comprobar rápidamente que la limpieza terminó
        # de forma razonable antes de pasar al análisis econométrico.
        # ---------------------------------------------------------------------

        print(
            f"\nFilas antes: {n_inicial} | "
            f"descartadas: {n_descartadas} | "
            f"finales: {n_final}"
        )

        print(
            f"Rango: {base['fecha'].min().date()} "
            f"a {base['fecha'].max().date()}"
        )

        print(
            "Guardado en: "
            f"datos_procesados/{os.path.basename(RUTA_SALIDA)}"
        )

        print(
            "Diagnóstico en: "
            f"datos_procesados/{os.path.basename(RUTA_DIAGNOSTICO)}"
        )

        print(
            f"SHA-256: {hash_sha256}"
        )

        print("\nPrimeras filas:")
        print(base.head().to_string(index=False))

        print("\nÚltimas filas:")
        print(base.tail().to_string(index=False))

        print("\nResumen estadístico:")
        print(
            base[columnas_valor]
            .describe()
            .round(2)
            .T
            .to_string()
        )

        logger.info("=== FIN 03_limpieza_datos ===")

    except Exception as error:
        logger.exception(
            f"Error en 03_limpieza_datos: {type(error).__name__}: {error}"
        )
        raise
