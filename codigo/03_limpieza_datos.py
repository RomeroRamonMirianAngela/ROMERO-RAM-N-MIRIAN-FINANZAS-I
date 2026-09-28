# Nombres y Apellidos completos: ROMERO RAMÓN MIRIAN ANGELA
# Codigo de matricula: 2024200523C
# Tema y numero del temario: Tema 37 - Política monetaria de la Reserva Federal y bonos soberanos peruanos
# Fecha de extraccion: 2026-09-24
# Fecha de limpieza (final): 2026-09-27
"""
03_limpieza_datos.py
--------------------

OBJETIVO
========
Este script prepara la base definitiva que utilizará 04_analisis.R, y el procedimiento parte
de los archivos crudos generados por 01_extraccion_api.py y realiza las siguientes tareas:


IMPORTANTE
==========
La winsorización no inventa observaciones ni elimina episodios económicos. Los
valores que exceden los límites IQR se sustituyen por el límite inferior o
superior correspondiente.
"""

import os
import re
import html
import hashlib
import logging
from io import StringIO

import pandas as pd


# =============================================================================
# 1. PARÁMETROS DEL PROYECTO
# =============================================================================

CODIGO_MATRICULA = "2024200523C"
FECHA_INICIO = "2010-01-01"
FECHA_CORTE = "2025-12-31"

# Series descargadas desde FRED y nombre económico utilizado en la base final.
SERIES_FRED = {
    "DFF": "tasa_fondos_federales",
    "DGS2": "tesoro_2a",
    "DGS10": "tesoro_10a",
}

# Estas cinco columnas son las variables originales necesarias para construir
# una observación completa antes de realizar transformaciones.
COLUMNAS_ORIGINALES = [
    "bono_pe_10a_soles",
    "embig_peru_pbs",
    "tasa_fondos_federales",
    "tesoro_2a",
    "tesoro_10a",
]

# Orden definitivo del archivo procesado. Se conservan las variables originales
# junto con las transformadas para que se pueda verificar el proceso.
COLUMNAS_PROCESADAS = [
    "bono_pe_10a_soles",
    "bono_pe_10a_soles_w",
    "embig_peru_pbs",
    "embig_peru_pp",
    "embig_peru_pp_w",
    "tasa_fondos_federales",
    "tesoro_2a",
    "tesoro_10a",
]


# =============================================================================
# 2. RUTAS DEL PROYECTO
# =============================================================================

RUTA_BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUTA_CRUDOS = os.path.join(RUTA_BASE, "datos_crudos")
RUTA_PROCESADOS = os.path.join(RUTA_BASE, "datos_procesados")
os.makedirs(RUTA_PROCESADOS, exist_ok=True)

RUTA_BONO = os.path.join(RUTA_CRUDOS, f"datos_crudos_bcrp_bono_10a_{CODIGO_MATRICULA}.csv")
RUTA_EMBIG = os.path.join(RUTA_CRUDOS, f"datos_crudos_bcrp_embig_{CODIGO_MATRICULA}.csv")


def ruta_fred(codigo_serie):
    """Devuelve la ruta del CSV crudo de una serie de FRED."""
    return os.path.join(RUTA_CRUDOS, f"datos_crudos_fred_{codigo_serie}_{CODIGO_MATRICULA}.csv")


RUTA_SALIDA = os.path.join(RUTA_PROCESADOS, f"datos_procesados_{CODIGO_MATRICULA}.csv")
RUTA_DIAGNOSTICO = os.path.join(RUTA_PROCESADOS, f"diagnostico_limpieza_{CODIGO_MATRICULA}.csv")
RUTA_TRATAMIENTO = os.path.join(RUTA_PROCESADOS, f"tratamiento_atipicos_{CODIGO_MATRICULA}.csv")
RUTA_LOG = os.path.join(RUTA_BASE, "log_ejecucion.txt")


# =============================================================================
# 3. REGISTRO DE EJECUCIÓN
# =============================================================================

# El modo "a" agrega nuevos mensajes al log existente sin borrar el registro de
# la extracción realizada por 01_extraccion_api.py.
logging.basicConfig(filename=RUTA_LOG, filemode="a", level=logging.INFO,
                    format="%(asctime)s | %(levelname)s | %(message)s", encoding="utf-8")
logger = logging.getLogger("limpieza_datos")


# =============================================================================
# 4. VALIDACIÓN DE ARCHIVOS DE ENTRADA
# =============================================================================

def verificar_archivo(ruta, etiqueta):
    """Comprueba que un archivo exista y tenga contenido antes de procesarlo."""
    if not os.path.isfile(ruta):
        raise FileNotFoundError(f"No se encontró el archivo de {etiqueta}:\n{ruta}\nEjecuta primero 01_extraccion_api.py.")
    if os.path.getsize(ruta) == 0:
        raise ValueError(f"El archivo de {etiqueta} está vacío: {ruta}")


# =============================================================================
# 5. LECTURA Y NORMALIZACIÓN DE LOS DATOS DEL BCRP
# =============================================================================

def corregir_formato_texto_bcrp(bytes_crudos):
    """Corrige únicamente la representación textual del CSV del BCRP."""
    texto = bytes_crudos.decode("utf-8", errors="replace")
    texto = re.sub(r"<br\s*/?>", "\n", texto, flags=re.IGNORECASE)
    try:
        texto = texto.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    texto = html.unescape(texto)
    return texto.strip() + "\n"


# Meses utilizados por BCRPData en las etiquetas de periodo.
MESES = {
    "ene": 1, "feb": 2, "mar": 3, "abr": 4, "may": 5, "jun": 6,
    "jul": 7, "ago": 8, "set": 9, "sep": 9, "oct": 10, "nov": 11, "dic": 12,
}


def normalizar_periodo(texto_periodo):
    """Convierte fechas textuales del BCRP a pandas.Timestamp."""
    if pd.isna(texto_periodo):
        return pd.NaT

    patron = r"^\s*(?:(\d{1,2})[.\-\s]?)?([A-Za-zÁÉÍÓÚáéíóúÑñ]{3})[.\-\s]?(\d{2,4})\s*$"
    coincidencia = re.match(patron, str(texto_periodo).strip())
    if not coincidencia:
        return pd.NaT

    dia, mes, anio = coincidencia.groups()
    mes = mes.lower()
    if mes not in MESES:
        return pd.NaT

    anio = int(anio)
    if anio < 100:
        anio += 2000

    try:
        return pd.Timestamp(year=anio, month=MESES[mes], day=int(dia or 1))
    except ValueError:
        return pd.NaT


def leer_bcrp_crudo(ruta_csv, nombre_columna):
    """Lee una serie cruda del BCRP y devuelve fecha + variable numérica."""
    verificar_archivo(ruta_csv, nombre_columna)

    with open(ruta_csv, "rb") as archivo:
        texto = corregir_formato_texto_bcrp(archivo.read())

    try:
        df = pd.read_csv(StringIO(texto), sep=",", dtype=str)
    except pd.errors.ParserError as error:
        raise ValueError(f"No se pudo interpretar el CSV del BCRP: {os.path.basename(ruta_csv)}") from error

    if df.shape[1] != 2:
        raise ValueError(f"Se esperaban 2 columnas en {os.path.basename(ruta_csv)}, pero se encontraron {df.shape[1]}.")

    df.columns = ["periodo", nombre_columna]
    df = df.dropna(how="all")
    df["fecha"] = df["periodo"].apply(normalizar_periodo)

    n_sin_fecha = int(df["fecha"].isna().sum())
    if n_sin_fecha:
        logger.warning(f"{nombre_columna}: {n_sin_fecha} filas con fecha no reconocida (se descartan)")

    valores = df[nombre_columna].astype("string").str.strip().replace({
        "": pd.NA, "n.d.": pd.NA, "n.d": pd.NA, "N.D.": pd.NA,
        "N.D": pd.NA, ".": pd.NA,
    })

    # Si apareciera coma decimal, se normaliza solo cuando el valor no contiene punto.
    mascara_coma = valores.str.contains(",", na=False) & ~valores.str.contains(r"\.", regex=True, na=False)
    valores.loc[mascara_coma] = valores.loc[mascara_coma].str.replace(",", ".", regex=False)
    df[nombre_columna] = pd.to_numeric(valores, errors="coerce")

    df = df.dropna(subset=["fecha"]).sort_values("fecha").drop_duplicates(subset="fecha", keep="last")
    df = df[df["fecha"].between(pd.Timestamp(FECHA_INICIO), pd.Timestamp(FECHA_CORTE), inclusive="both")]
    logger.info(f"{nombre_columna}: {len(df)} filas leidas del crudo BCRP")
    return df[["fecha", nombre_columna]].reset_index(drop=True)


# =============================================================================
# 6. LECTURA Y NORMALIZACIÓN DE LOS DATOS DE FRED
# =============================================================================

def _detectar_columna(columnas, candidatos):
    """Busca una columna ignorando diferencias de mayúsculas y espacios."""
    mapa = {str(col).strip().lower(): col for col in columnas}
    for candidato in candidatos:
        if candidato.lower() in mapa:
            return mapa[candidato.lower()]
    return None


def leer_fred_csv(ruta_csv, codigo_serie, nombre_columna):
    """Lee el CSV crudo oficial de una serie de FRED."""
    verificar_archivo(ruta_csv, f"FRED {codigo_serie}")

    try:
        df = pd.read_csv(ruta_csv, dtype=str, encoding="utf-8-sig")
    except UnicodeDecodeError:
        df = pd.read_csv(ruta_csv, dtype=str, encoding="latin-1")
    except pd.errors.ParserError as error:
        raise ValueError(f"No se pudo interpretar el CSV de FRED {codigo_serie}: {os.path.basename(ruta_csv)}") from error

    if df.empty:
        raise ValueError(f"El CSV de FRED {codigo_serie} no contiene observaciones.")

    columna_fecha = _detectar_columna(df.columns, ["period_start_date", "date", "observation_date", "fecha"])
    columna_valor = _detectar_columna(df.columns, [codigo_serie, "value"])

    if columna_fecha is None:
        raise ValueError(f"No se encontró una columna de fecha en {os.path.basename(ruta_csv)}. Columnas: {list(df.columns)}")
    if columna_valor is None:
        raise ValueError(f"No se encontró la columna de valores de {codigo_serie} en {os.path.basename(ruta_csv)}. Columnas: {list(df.columns)}")

    serie = pd.DataFrame({
        "fecha": pd.to_datetime(df[columna_fecha].astype("string").str.strip(), errors="coerce"),
        nombre_columna: pd.to_numeric(
            df[columna_valor].astype("string").str.strip().replace({"": pd.NA, ".": pd.NA, "nan": pd.NA, "NaN": pd.NA}),
            errors="coerce",
        ),
    })

    n_sin_fecha = int(serie["fecha"].isna().sum())
    if n_sin_fecha:
        logger.warning(f"{nombre_columna} ({codigo_serie}): {n_sin_fecha} filas con fecha invalida (se descartan)")

    serie = serie.dropna(subset=["fecha"]).sort_values("fecha").drop_duplicates(subset="fecha", keep="last")
    serie = serie[serie["fecha"].between(pd.Timestamp(FECHA_INICIO), pd.Timestamp(FECHA_CORTE), inclusive="both")]
    logger.info(f"{nombre_columna} ({codigo_serie}): {len(serie)} filas leidas del crudo FRED")
    return serie[["fecha", nombre_columna]].reset_index(drop=True)


def leer_fred_crudo(series):
    """Lee DFF, DGS2 y DGS10 y las une en una sola tabla por fecha."""
    partes = []
    for codigo, nombre in series.items():
        partes.append(leer_fred_csv(ruta_fred(codigo), codigo, nombre).set_index("fecha"))
    if not partes:
        raise ValueError("No se definieron series de FRED para procesar.")
    return pd.concat(partes, axis=1, join="outer").sort_index().reset_index()


# =============================================================================
# 7. CALENDARIO COMÚN Y UNIÓN DE LAS FUENTES
# =============================================================================

def unir_en_calendario(tablas):
    """Une todas las fuentes sobre un calendario común de lunes a viernes."""
    base = pd.DataFrame({"fecha": pd.bdate_range(start=FECHA_INICIO, end=FECHA_CORTE)})
    for tabla in tablas:
        if "fecha" not in tabla.columns:
            raise ValueError("Todas las tablas deben contener la columna 'fecha'.")
        base = base.merge(tabla, on="fecha", how="left", validate="one_to_one")
    return base


# =============================================================================
# 8. DIAGNÓSTICO DE FALTANTES Y POSIBLES ATÍPICOS
# =============================================================================

def diagnosticar(base, columnas):
    """Documenta faltantes y posibles atípicos IQR antes del tratamiento."""
    filas = []
    for columna in columnas:
        datos = base[columna].dropna()

        if datos.empty:
            limite_inf, limite_sup, n_atipicos = float("nan"), float("nan"), 0
        else:
            q1, q3 = datos.quantile([0.25, 0.75])
            iqr = q3 - q1
            limite_inf, limite_sup = q1 - 1.5 * iqr, q3 + 1.5 * iqr
            n_atipicos = int(((base[columna] < limite_inf) | (base[columna] > limite_sup)).sum())

        filas.append({
            "variable": columna,
            "dias_habiles": len(base),
            "dias_con_dato": int(base[columna].notna().sum()),
            "dias_sin_dato": int(base[columna].isna().sum()),
            "posibles_atipicos": n_atipicos,
            "limite_inferior": round(float(limite_inf), 4) if pd.notna(limite_inf) else float("nan"),
            "limite_superior": round(float(limite_sup), 4) if pd.notna(limite_sup) else float("nan"),
        })

    return pd.DataFrame(filas)


# =============================================================================
# 9. CONVERSIÓN DE UNIDADES Y TRATAMIENTO DE VALORES ATÍPICOS
# =============================================================================

def winsorizar_iqr(serie):
    """
    Winsoriza una serie utilizando límites IQR.

    Los valores menores a Q1 - 1.5*IQR se sustituyen por el límite inferior y
    los valores mayores a Q3 + 1.5*IQR se sustituyen por el límite superior.
    La función devuelve la serie tratada y los parámetros utilizados.
    """
    q1 = serie.quantile(0.25)
    q3 = serie.quantile(0.75)
    iqr = q3 - q1
    limite_inf = q1 - 1.5 * iqr
    limite_sup = q3 + 1.5 * iqr
    serie_w = serie.clip(lower=limite_inf, upper=limite_sup)

    resumen = {
        "q1": q1,
        "q3": q3,
        "iqr": iqr,
        "limite_inferior": limite_inf,
        "limite_superior": limite_sup,
        "n_atipicos": int(((serie < limite_inf) | (serie > limite_sup)).sum()),
        "n_modificados": int((serie != serie_w).sum()),
    }
    return serie_w, resumen


def aplicar_tratamiento_atipicos(base):
    """
    Convierte EMBIG a puntos porcentuales y winsoriza las dos variables
    peruanas utilizadas en el análisis final.
    """
    base = base.copy()

    # Bono, Fed Funds y Treasuries ya están expresados en porcentaje. El EMBIG
    # viene en puntos básicos, por eso se divide entre 100.
    base["embig_peru_pp"] = base["embig_peru_pbs"] / 100

    base["bono_pe_10a_soles_w"], resumen_bono = winsorizar_iqr(base["bono_pe_10a_soles"])
    base["embig_peru_pp_w"], resumen_embig = winsorizar_iqr(base["embig_peru_pp"])

    tratamiento = pd.DataFrame([
        {"variable": "bono_pe_10a_soles", **resumen_bono},
        {"variable": "embig_peru_pp", **resumen_embig},
    ])

    # Se redondea únicamente la tabla de diagnóstico; la base conserva toda la
    # precisión numérica de las transformaciones.
    columnas_numericas = tratamiento.select_dtypes(include="number").columns
    tratamiento[columnas_numericas] = tratamiento[columnas_numericas].round(6)
    return base, tratamiento


# =============================================================================
# 10. HASH DE INTEGRIDAD
# =============================================================================

def calcular_sha256(ruta):
    """Calcula el SHA-256 del archivo procesado que será declarado en README."""
    hash_obj = hashlib.sha256()
    with open(ruta, "rb") as archivo:
        for bloque in iter(lambda: archivo.read(65536), b""):
            hash_obj.update(bloque)
    return hash_obj.hexdigest()


# =============================================================================
# 11. EJECUCIÓN COMPLETA DE LA LIMPIEZA
# =============================================================================

if __name__ == "__main__":
    logger.info("=== INICIO 03_limpieza_datos ===")
    logger.info(f"Parametros congelados: FECHA_INICIO={FECHA_INICIO} | FECHA_CORTE={FECHA_CORTE}")

    try:
        # 1. Se verifica que estén disponibles los cinco archivos crudos.
        verificar_archivo(RUTA_BONO, "bono soberano peruano a 10 años")
        verificar_archivo(RUTA_EMBIG, "EMBIG Perú")
        for codigo in SERIES_FRED:
            verificar_archivo(ruta_fred(codigo), f"FRED {codigo}")

        # 2. Lectura y tipificación de las cinco series originales.
        bono = leer_bcrp_crudo(RUTA_BONO, "bono_pe_10a_soles")
        embig = leer_bcrp_crudo(RUTA_EMBIG, "embig_peru_pbs")
        fred = leer_fred_crudo(SERIES_FRED)

        # 3. Unión por fecha utilizando un calendario común de días hábiles.
        base = unir_en_calendario([bono, embig, fred])
        faltantes_columnas = set(COLUMNAS_ORIGINALES) - set(base.columns)
        if faltantes_columnas:
            raise ValueError("Faltan variables esperadas después de unir las fuentes: " + ", ".join(sorted(faltantes_columnas)))

        base = base[["fecha"] + COLUMNAS_ORIGINALES]
        n_inicial = len(base)

        # 4. Diagnóstico previo. Esta tabla documenta la situación observada
        # antes de eliminar filas incompletas y antes de winsorizar.
        diagnostico = diagnosticar(base, COLUMNAS_ORIGINALES)
        diagnostico.to_csv(RUTA_DIAGNOSTICO, index=False, encoding="utf-8", lineterminator="\n")
        print("Diagnóstico de faltantes y posibles atípicos antes del tratamiento:")
        print(diagnostico.to_string(index=False))

        for _, fila in diagnostico.iterrows():
            logger.info(
                f"{fila['variable']}: {fila['dias_sin_dato']} dias sin dato | "
                f"{fila['posibles_atipicos']} posibles atipicos antes del tratamiento"
            )

        # 5. Se conservan únicamente las fechas con dato en las cinco variables
        # originales. No se imputan valores ni se generan observaciones nuevas.
        base = base.dropna(subset=COLUMNAS_ORIGINALES).reset_index(drop=True)
        n_final = len(base)
        n_descartadas = n_inicial - n_final
        logger.info(f"Filas antes: {n_inicial} | descartadas por faltantes: {n_descartadas} | completas: {n_final}")

        # 6. Conversión del EMBIG y winsorización IQR de las variables peruanas.
        # El tratamiento se calcula sobre la misma muestra completa que usará R.
        base, tratamiento = aplicar_tratamiento_atipicos(base)
        tratamiento.to_csv(RUTA_TRATAMIENTO, index=False, encoding="utf-8", lineterminator="\n")

        for _, fila in tratamiento.iterrows():
            logger.info(
                f"{fila['variable']}: {int(fila['n_atipicos'])} atipicos IQR | "
                f"{int(fila['n_modificados'])} observaciones winsorizadas | "
                f"limites=({fila['limite_inferior']}, {fila['limite_superior']})"
            )

        # 7. Validaciones de consistencia de la base ya procesada.
        if base.empty:
            raise ValueError("La base final quedó vacía después del tratamiento de faltantes.")
        if not base["fecha"].is_unique:
            raise ValueError("Hay fechas duplicadas en la base final.")
        if not base["fecha"].is_monotonic_increasing:
            raise ValueError("Las fechas no están ordenadas de forma ascendente.")
        if base[COLUMNAS_PROCESADAS].isna().any().any():
            raise ValueError("Quedaron valores vacíos en la base final procesada.")
        if not base["fecha"].between(pd.Timestamp(FECHA_INICIO), pd.Timestamp(FECHA_CORTE), inclusive="both").all():
            raise ValueError("Hay fechas fuera del periodo oficial del estudio.")
        if (base["fecha"].dt.dayofweek > 4).any():
            raise ValueError("La base final contiene fines de semana.")

        # Comprueba que la conversión de puntos básicos a puntos porcentuales
        # sea exactamente la definida metodológicamente: 100 pbs = 1 p.p.
        diferencia_embig = (base["embig_peru_pp"] - base["embig_peru_pbs"] / 100).abs()
        if not (diferencia_embig < 1e-12).all():
            raise ValueError("La conversión del EMBIG a puntos porcentuales no es consistente.")

        if n_final < 1000:
            logger.warning(f"La base tiene {n_final} observaciones (menos del minimo de 1000).")

        # 8. Orden definitivo de columnas y guardado del archivo procesado.
        base = base[["fecha"] + COLUMNAS_PROCESADAS]
        base_salida = base.copy()
        base_salida["fecha"] = base_salida["fecha"].dt.strftime("%Y-%m-%d")
        base_salida.to_csv(RUTA_SALIDA, index=False, encoding="utf-8", lineterminator="\n")

        # 9. El hash identifica exactamente la versión del archivo procesado que
        # será utilizada en el análisis y posteriormente declarada en README.
        hash_sha256 = calcular_sha256(RUTA_SALIDA)
        logger.info(f"Base procesada guardada en: datos_procesados/{os.path.basename(RUTA_SALIDA)}")
        logger.info(f"SHA-256 de {os.path.basename(RUTA_SALIDA)}: {hash_sha256}")

        # 10. Resumen de ejecución para facilitar la revisión del profesor.
        print(f"\nFilas del calendario: {n_inicial}")
        print(f"Filas descartadas por faltantes: {n_descartadas}")
        print(f"Filas finales procesadas: {n_final}")
        print(f"Rango: {base['fecha'].min().date()} a {base['fecha'].max().date()}")
        print(f"Guardado en: datos_procesados/{os.path.basename(RUTA_SALIDA)}")
        print(f"Diagnóstico inicial: datos_procesados/{os.path.basename(RUTA_DIAGNOSTICO)}")
        print(f"Tratamiento de atípicos: datos_procesados/{os.path.basename(RUTA_TRATAMIENTO)}")
        print(f"SHA-256: {hash_sha256}")

        print("\nTratamiento de valores atípicos:")
        print(tratamiento.to_string(index=False))

        print("\nPrimeras filas de la base procesada:")
        print(base.head().to_string(index=False))

        print("\nÚltimas filas de la base procesada:")
        print(base.tail().to_string(index=False))

        print("\nResumen estadístico de las variables procesadas:")
        print(base[COLUMNAS_PROCESADAS].describe().round(4).T.to_string())

        logger.info("=== FIN 03_limpieza_datos ===")

    except Exception as error:
        logger.exception(f"Error en 03_limpieza_datos: {type(error).__name__}: {error}")
        raise
