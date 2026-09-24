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
01_extraccion_api.py
--------------------

OBJETIVO GENERAL
================
Descargar mediante API las series económicas necesarias para el estudio y
guardar una copia de los datos crudos en la carpeta /datos_crudos.

FUENTES UTILIZADAS
==================

1. BCRPData
   Banco Central de Reserva del Perú.

   Series:
   - PD31893DD:
     rendimiento del bono soberano peruano a 10 años (S/), frecuencia diaria.
   - PD04709XD:
     EMBIG Perú, indicador de riesgo país expresado en puntos básicos.

   Endpoint general:
   https://estadisticas.bcrp.gob.pe/estadisticas/series/api

2. FRED
   Federal Reserve Economic Data, Federal Reserve Bank of St. Louis.

   Series:
   - DFF:
     Effective Federal Funds Rate.
   - DGS2:
     rendimiento del Treasury de Estados Unidos a 2 años.
   - DGS10:
     rendimiento del Treasury de Estados Unidos a 10 años.

   Endpoint:
   https://api.stlouisfed.org/fred/series/observations

   Para utilizar esta API se requiere una clave denominada FRED_API_KEY.
   Por seguridad, la clave NO se escribe directamente en este programa.
   Se guarda en el archivo .env ubicado en la raíz del proyecto, pero usted 
   lo puede generar desde la página oficial de FRED:
    https://fred.stlouisfed.org/docs/api/api_key.html


   Recordemos que cuando FRED recibe el parámetro: file_type = "csv"

   Este devuelve un archivo ZIP que contiene el CSV correspondiente.

   Por ello, este programa:

       1. solicita el archivo a FRED;
       2. recibe el ZIP;
       3. abre el ZIP directamente en memoria;
       4. localiza el archivo CSV;
       5. extrae su contenido;
       6. guarda el CSV en /datos_crudos.

       
ESTRUCTURA ESPERADA DEL PROYECTO
================================

ROMERO-RAM-N-MIRIAN-FINANZAS-I/
│
├── .env
├── log_ejecucion.txt
│
├── codigo/
│   ├── 01_extraccion_api.py
│   ├── 03_limpieza_datos.py
│   └── 04_analisis.R
│
├── datos_crudos/
│
└── datos_procesados/


FLUJO DE TRABAJO
================

01_extraccion_api.py
        ↓
Datos originales descargados
        ↓
03_limpieza_datos.py
        ↓
Base limpia y unificada
        ↓
04_analisis.R
        ↓
Análisis estadístico y econométrico
"""


# =============================================================================
# PASO 1. IMPORTAR LAS LIBRERÍAS NECESARIAS
# =============================================================================

import io
import os
import time
import logging
import zipfile

import requests
from dotenv import load_dotenv


# =============================================================================
# PASO 2. DEFINIR LOS PARÁMETROS FIJOS DEL ESTUDIO
# =============================================================================
#
# Estos parámetros se declaran al inicio para que todo el programa utilice
# exactamente la misma información.
#
# Mantener las fechas como constantes también ayuda a la reproducibilidad:
# si el programa se ejecuta nuevamente, el periodo solicitado no cambia.
# =============================================================================

# Código de matrícula.
# Se incorpora en los nombres de los archivos para identificarlos.
CODIGO_MATRICULA = "2024200523C"

# Primera fecha incluida en el estudio.
FECHA_INICIO = "2010-01-01"

# Última fecha incluida en el estudio.
FECHA_CORTE = "2025-12-31"

# Idioma solicitado a la API del BCRP.
IDIOMA = "esp"


# =============================================================================
# PASO 3. DECLARAR LAS SERIES QUE SE DESCARGARÁN DEL BCRP
# =============================================================================
#
# Aquí se utilizó una lista de diccionarios para cada serie se guarda:
#
#   nombre  -> descripción que aparecerá en pantalla;
#   codigo  -> código oficial utilizado por la API del BCRP;
#   archivo -> nombre con el que se almacenará el dato crudo.
#
# Esta estructura permite recorrer todas las series utilizando un solo bucle.
# =============================================================================

FUENTES_BCRP = [
    {
        "nombre": "bono soberano peruano 10 años",
        "codigo": "PD31893DD",
        "archivo": (
            f"datos_crudos_bcrp_bono_10a_"
            f"{CODIGO_MATRICULA}.csv"
        ),
    },
    {
        "nombre": "EMBIG Perú",
        "codigo": "PD04709XD",
        "archivo": (
            f"datos_crudos_bcrp_embig_"
            f"{CODIGO_MATRICULA}.csv"
        ),
    },
]


# =============================================================================
# PASO 4. DECLARAR LAS SERIES QUE SE DESCARGARÁN DE FRED
# =============================================================================
#
# Los códigos utilizados son los códigos oficiales de las series en FRED.
#
# DFF   -> tasa efectiva de fondos federales.
# DGS2  -> rendimiento del Treasury de EE. UU. a 2 años.
# DGS10 -> rendimiento del Treasury de EE. UU. a 10 años.
#
# Cada serie se guardará posteriormente como un archivo CSV independiente.
# =============================================================================

SERIES_FRED = [
    "DFF",
    "DGS2",
    "DGS10",
]


# =============================================================================
# PASO 5. DEFINIR LAS DIRECCIONES BASE DE LAS APIs
# =============================================================================
#
# Se separan las URL principales de los parámetros de consulta.
# =============================================================================

URL_BCRP = (
    "https://estadisticas.bcrp.gob.pe/"
    "estadisticas/series/api"
)

URL_FRED = (
    "https://api.stlouisfed.org/"
    "fred/series/observations"
)


# =============================================================================
# PASO 6. CONFIGURAR EL COMPORTAMIENTO GENERAL DE LAS SOLICITUDES
# =============================================================================

# Número de segundos que se espera entre una consulta y la siguiente.
#
# La pausa evita enviar varias solicitudes consecutivas de forma innecesaria
# y constituye una buena práctica al consumir servicios API.
PAUSA_SEG = 1


# User-Agent enviado junto con las solicitudes HTTP.
#
# Sirve para identificar de manera general el origen de la consulta.
CABECERAS = {
    "User-Agent": (
        f"Finanzas-I-UNCP-2026-II "
        f"(trabajo academico; "
        f"matricula {CODIGO_MATRICULA})"
    )
}


# =============================================================================
# PASO 7. CONSTRUIR LAS RUTAS DEL PROYECTO
# =============================================================================
#
# Se calcula automáticamente la ubicación del proyecto con: 
#
# __file__
#     representa la ubicación de este propio script.
#
# os.path.abspath(__file__)
#     obtiene su ruta absoluta.
#
# os.path.dirname(...)
#     permite subir desde /codigo hasta la raíz del proyecto.
#
# =============================================================================

RUTA_BASE = os.path.dirname(
    os.path.dirname(
        os.path.abspath(__file__)
    )
)


# Ruta donde se almacenarán los datos originales descargados.
RUTA_CRUDOS = os.path.join(
    RUTA_BASE,
    "datos_crudos",
)


# Si la carpeta /datos_crudos todavía no existe, se crea.
#
# exist_ok=True evita generar un error si la carpeta ya estaba creada.
os.makedirs(
    RUTA_CRUDOS,
    exist_ok=True,
)


# Ruta del archivo donde se registrarán las ejecuciones.
RUTA_LOG = os.path.join(
    RUTA_BASE,
    "log_ejecucion.txt",
)


# =============================================================================
# PASO 8. CONFIGURAR EL ARCHIVO DE REGISTRO (LOG)
# =============================================================================
#
# El log funciona como evidencia de la ejecución del proceso y se registra: 
#
# - fecha y hora;
# - inicio y fin del programa;
# - código HTTP de cada solicitud;
# - cantidad de datos descargados;
# - errores de conexión;
# - nombres de los archivos generados.
#
# filemode="a"
#     significa append: agrega nueva información al final y no elimina el
#     contenido de ejecuciones anteriores.
#
# encoding="utf-8"
#     permite escribir caracteres como ñ y tildes.
# =============================================================================

logging.basicConfig(
    filename=RUTA_LOG,
    filemode="a",
    level=logging.INFO,
    format=(
        "%(asctime)s | "
        "%(levelname)s | "
        "%(message)s"
    ),
    encoding="utf-8",
)


# Se crea un logger específico para este script.
logger = logging.getLogger(
    "extraccion_api"
)


# =============================================================================
# PASO 9. CREAR UNA FUNCIÓN GENERAL PARA CONSULTAR LAS APIs
# =============================================================================
#
# Esta función se reutiliza tanto para BCRP como para FRED.
#
# Recibe:
#
#   url
#       dirección de la API;
#
#   etiqueta
#       nombre utilizado para identificar la consulta en el log;
#
#   params
#       parámetros que se enviarán con la consulta;
#
#   max_reintentos
#       número máximo de intentos si ocurre un problema;
#
#   espera_seg
#       segundos que se esperan antes de volver a intentar.
#
# Devuelve:
#
#   respuesta.content
#       contenido recibido en formato bytes.
#
# Trabajar con bytes permite conservar el archivo descargado sin modificar
# innecesariamente su contenido.
# =============================================================================

def solicitar_api(
    url,
    etiqueta,
    params=None,
    max_reintentos=3,
    espera_seg=2,
):
    """
    Realiza una solicitud HTTP GET y devuelve el contenido recibido en bytes.

    Si la conexión falla o la respuesta HTTP no es 200, se realizan nuevos
    intentos hasta llegar al máximo definido.

    Por seguridad, el log NO almacena la URL completa de FRED, ya que entre
    los parámetros de esa consulta se encuentra la clave personal de la API.
    """

    # El bucle comienza en 1 para que el número de intento sea fácil de leer.
    for intento in range(
        1,
        max_reintentos + 1,
    ):

        try:

            # -----------------------------------------------------------------
            # 9.1. REALIZAR LA SOLICITUD HTTP
            # -----------------------------------------------------------------
            #
            # requests.get envía una consulta GET.
            #
            # timeout=60 evita que el programa permanezca indefinidamente
            # esperando una respuesta si existe un problema de conexión.
            # -----------------------------------------------------------------

            respuesta = requests.get(
                url,
                params=params,
                headers=CABECERAS,
                timeout=60,
            )


            # -----------------------------------------------------------------
            # 9.2. REGISTRAR EL CÓDIGO HTTP
            # -----------------------------------------------------------------
            #
            # Código 200 significa que la solicitud fue atendida correctamente.
            # -----------------------------------------------------------------

            logger.info(
                f"{etiqueta} | "
                f"intento {intento} | "
                f"codigo HTTP: "
                f"{respuesta.status_code}"
            )


            # -----------------------------------------------------------------
            # 9.3. SI LA RESPUESTA ES CORRECTA, DEVOLVER LOS DATOS
            # -----------------------------------------------------------------

            if respuesta.status_code == 200:

                return respuesta.content


            # -----------------------------------------------------------------
            # 9.4. SI EL SERVIDOR RESPONDE CON OTRO CÓDIGO, REGISTRARLO
            # -----------------------------------------------------------------

            logger.warning(
                f"{etiqueta} | "
                f"HTTP {respuesta.status_code}. "
                f"Reintentando..."
            )


        except requests.exceptions.RequestException as error:

            # -----------------------------------------------------------------
            # 9.5. CAPTURAR ERRORES DE CONEXIÓN
            # -----------------------------------------------------------------
            #
            # Puede tratarse, por ejemplo, de:
            #
            # - pérdida de internet;
            # - tiempo de espera agotado;
            # - error de conexión con el servidor.
            #
            # Se registra únicamente el tipo de error.
            # No se almacena la URL completa para evitar que la clave de FRED
            # pueda terminar accidentalmente escrita en el log.
            # -----------------------------------------------------------------

            logger.error(
                f"{etiqueta} | "
                f"intento {intento} | "
                f"error de conexion: "
                f"{type(error).__name__}"
            )


        # ---------------------------------------------------------------------
        # 9.6. ESPERAR ANTES DEL SIGUIENTE INTENTO
        # ---------------------------------------------------------------------
        #
        # La espera solo se realiza cuando todavía queda otro intento.
        # ---------------------------------------------------------------------

        if intento < max_reintentos:

            time.sleep(
                espera_seg
            )


    # -------------------------------------------------------------------------
    # 9.7. DETENER EL PROCESO SI TODOS LOS INTENTOS FALLAN
    # -------------------------------------------------------------------------
    #
    # Es preferible detener la ejecución antes que continuar con datos
    # incompletos o inexistentes.
    # -------------------------------------------------------------------------

    raise ConnectionError(
        f"No fue posible obtener "
        f"{etiqueta} tras "
        f"{max_reintentos} intentos."
    )


# =============================================================================
# PASO 10. CREAR UNA FUNCIÓN PARA GUARDAR LOS DATOS CRUDOS
# =============================================================================
#
# Esta función centraliza el guardado de todos los archivos descargados.
#
# El archivo se abre con "wb":
#
#   w -> escritura;
#   b -> modo binario.
#
# Esto permite escribir directamente los bytes recibidos desde las APIs.
# =============================================================================

def guardar_crudo(
    contenido,
    nombre_archivo,
):
    """
    Guarda el contenido recibido dentro de la carpeta /datos_crudos.

    La función devuelve la ruta final del archivo para poder utilizarla
    posteriormente en los mensajes de pantalla y en el registro.
    """

    # Combinar la carpeta /datos_crudos con el nombre del archivo.
    ruta = os.path.join(
        RUTA_CRUDOS,
        nombre_archivo,
    )


    # Abrir el archivo en modo binario y escribir el contenido.
    with open(
        ruta,
        "wb",
    ) as archivo:

        archivo.write(
            contenido
        )


    # Devolver la ubicación donde se guardó el archivo.
    return ruta


# =============================================================================
# PASO 11. CREAR LA FUNCIÓN DE EXTRACCIÓN DEL BCRP
# =============================================================================
# La función realiza cuatro tareas:
#
# 1. construir la URL;
# 2. descargar el contenido;
# 3. guardar el archivo;
# 4. registrar y mostrar un resumen.
# =============================================================================

def extraer_bcrp(
    fuente,
):
    """
    Descarga una serie del BCRP en formato CSV y conserva el contenido recibido.
    """

    # -------------------------------------------------------------------------
    # 11.1. CONSTRUIR LA URL ESPECÍFICA DE LA SERIE
    # -------------------------------------------------------------------------

    url = (
        f"{URL_BCRP}/"
        f"{fuente['codigo']}/csv/"
        f"{FECHA_INICIO}/"
        f"{FECHA_CORTE}/"
        f"{IDIOMA}"
    )


    # Etiqueta utilizada en el log.
    etiqueta = (
        f"BCRP "
        f"{fuente['codigo']}"
    )


    # -------------------------------------------------------------------------
    # 11.2. DESCARGAR LOS DATOS
    # -------------------------------------------------------------------------
    #
    # Se reutiliza solicitar_api(), por lo que ya están incluidos:
    #
    # - timeout;
    # - registro del código HTTP;
    # - reintentos;
    # - manejo de errores de conexión.
    # -------------------------------------------------------------------------

    contenido = solicitar_api(
        url,
        etiqueta,
    )


    # -------------------------------------------------------------------------
    # 11.3. GUARDAR EL ARCHIVO CRUDO
    # -------------------------------------------------------------------------

    ruta = guardar_crudo(
        contenido,
        fuente["archivo"],
    )


    # -------------------------------------------------------------------------
    # 11.4. CALCULAR UNA CANTIDAD APROXIMADA DE FILAS
    # -------------------------------------------------------------------------
    #
    # En la respuesta del BCRP los registros pueden estar separados mediante
    # la etiqueta HTML <br>.
    #
    # Contar estas apariciones permite mostrar una referencia rápida de cuántos
    # registros fueron recibidos.
    #
    # Este conteo solo es informativo. La limpieza real de los datos se realiza
    # posteriormente en 03_limpieza_datos.py.
    # -------------------------------------------------------------------------

    n_filas = contenido.count(
        b"<br>"
    )


    # -------------------------------------------------------------------------
    # 11.5. REGISTRAR LA DESCARGA EN EL LOG
    # -------------------------------------------------------------------------

    logger.info(
        f"{etiqueta} | "
        f"filas descargadas: ~{n_filas} | "
        f"archivo: {fuente['archivo']}"
    )


    # -------------------------------------------------------------------------
    # 11.6. MOSTRAR EL RESULTADO EN LA CONSOLA
    # -------------------------------------------------------------------------

    print(
        f"[BCRP] "
        f"{fuente['nombre']}: "
        f"~{n_filas} filas -> "
        f"{os.path.relpath(ruta, RUTA_BASE)}"
    )


# =============================================================================
# PASO 12. CREAR LA FUNCIÓN DE EXTRACCIÓN DE FRED
# =============================================================================
#
# A diferencia del BCRP, FRED recibe los parámetros mediante params.
#
# Parámetros principales:
#
# series_id
#     identifica la serie.
#
# api_key
#     clave personal utilizada para acceder a FRED.
#
# file_type
#     se solicita CSV.
#
# observation_start
#     fecha inicial.
#
# observation_end
#     fecha final.
#
# IMPORTANTE:
#
# FRED no devuelve directamente el CSV cuando se solicita file_type="csv".
# Devuelve un ZIP. Por ello, el programa debe abrirlo antes de guardar el CSV.
# =============================================================================

def extraer_fred(
    codigo_serie,
    clave_api,
):
    """
    Descarga una serie de FRED en formato CSV.

    El archivo llega comprimido dentro de un ZIP. El ZIP se abre en memoria
    y únicamente se guarda el CSV que contiene la serie solicitada.
    """


    # -------------------------------------------------------------------------
    # 12.1. PREPARAR LOS PARÁMETROS DE LA CONSULTA
    # -------------------------------------------------------------------------

    params = {
        "series_id": codigo_serie,
        "api_key": clave_api,
        "file_type": "csv",
        "observation_start": FECHA_INICIO,
        "observation_end": FECHA_CORTE,
    }


    # Etiqueta que permitirá identificar la serie en el log.
    etiqueta = (
        f"FRED "
        f"{codigo_serie}"
    )


    # -------------------------------------------------------------------------
    # 12.2. DESCARGAR EL ARCHIVO ZIP
    # -------------------------------------------------------------------------

    contenido_zip = solicitar_api(
        URL_FRED,
        etiqueta,
        params=params,
    )


    # -------------------------------------------------------------------------
    # 12.3. ABRIR EL ZIP DIRECTAMENTE EN MEMORIA
    # -------------------------------------------------------------------------
    #
    # io.BytesIO transforma los bytes recibidos en un objeto que zipfile puede
    # tratar como si fuera un archivo.
    #
    # Así no es necesario guardar un ZIP temporal en el disco.
    # -------------------------------------------------------------------------

    try:

        with zipfile.ZipFile(
            io.BytesIO(
                contenido_zip
            )
        ) as archivo_zip:


            # -----------------------------------------------------------------
            # 12.4. IDENTIFICAR LOS ARCHIVOS CSV DEL ZIP
            # -----------------------------------------------------------------
            #
            # namelist() devuelve la lista de nombres contenidos en el ZIP.
            #
            # Se conservan únicamente aquellos que terminan en ".csv".
            # -----------------------------------------------------------------

            archivos_csv = [
                nombre
                for nombre
                in archivo_zip.namelist()
                if nombre.lower().endswith(
                    ".csv"
                )
            ]


            # -----------------------------------------------------------------
            # 12.5. VALIDAR QUE EL ZIP REALMENTE CONTENGA UN CSV
            # -----------------------------------------------------------------
            #
            # Si no existe ningún CSV, el programa se detiene.
            # Esto evita guardar información incorrecta como si fuera una serie.
            # -----------------------------------------------------------------

            if not archivos_csv:

                logger.error(
                    f"{etiqueta} | "
                    f"el ZIP no contiene CSV"
                )

                raise ValueError(
                    f"FRED no devolvió un archivo CSV "
                    f"para la serie {codigo_serie}."
                )


            # -----------------------------------------------------------------
            # 12.6. SELECCIONAR EL CSV
            # -----------------------------------------------------------------
            #
            # Para esta consulta se espera un CSV principal.
            # Se toma el primero de la lista encontrada.
            # -----------------------------------------------------------------

            nombre_csv_en_zip = (
                archivos_csv[0]
            )


            # -----------------------------------------------------------------
            # 12.7. LEER EL CSV DESDE EL ZIP
            # -----------------------------------------------------------------
            #
            # read() devuelve nuevamente el contenido en bytes.
            # Todavía no se transforma ni se limpia el dato.
            # -----------------------------------------------------------------

            contenido_csv = archivo_zip.read(
                nombre_csv_en_zip
            )


    # -------------------------------------------------------------------------
    # 12.8. CONTROLAR EL CASO EN QUE LA RESPUESTA NO SEA UN ZIP VÁLIDO
    # -------------------------------------------------------------------------
    #
    # Esto permite detectar una respuesta inesperada antes de crear un archivo
    # incorrecto en /datos_crudos.
    # -------------------------------------------------------------------------

    except zipfile.BadZipFile as error:

        logger.error(
            f"{etiqueta} | "
            f"la respuesta recibida "
            f"no es un ZIP valido"
        )


        raise ValueError(
            f"FRED no devolvió un ZIP válido "
            f"para la serie {codigo_serie}."
        ) from error


    # -------------------------------------------------------------------------
    # 12.9. CREAR EL NOMBRE DEL ARCHIVO DE SALIDA
    # -------------------------------------------------------------------------
    #
    # Ejemplos:
    #
    # datos_crudos_fred_DFF_2024200523C.csv
    # datos_crudos_fred_DGS2_2024200523C.csv
    # datos_crudos_fred_DGS10_2024200523C.csv
    # -------------------------------------------------------------------------

    nombre_archivo = (
        f"datos_crudos_fred_"
        f"{codigo_serie}_"
        f"{CODIGO_MATRICULA}.csv"
    )


    # -------------------------------------------------------------------------
    # 12.10. GUARDAR EL CSV EXTRAÍDO
    # -------------------------------------------------------------------------

    ruta = guardar_crudo(
        contenido_csv,
        nombre_archivo,
    )


    # -------------------------------------------------------------------------
    # 12.11. CONTAR LAS OBSERVACIONES DEL CSV
    # -------------------------------------------------------------------------
    #
    # splitlines() separa el contenido por filas.
    #
    # El CSV contiene una fila de encabezados, por lo que se resta 1.
    #
    # max(..., 0) impide obtener un valor negativo si llegara un archivo vacío.
    # -------------------------------------------------------------------------

    total_lineas = len(
        contenido_csv.splitlines()
    )


    n_filas = max(
        total_lineas - 1,
        0,
    )


    # -------------------------------------------------------------------------
    # 12.12. REGISTRAR LA DESCARGA
    # -------------------------------------------------------------------------

    logger.info(
        f"{etiqueta} | "
        f"filas descargadas: {n_filas} | "
        f"archivo: {nombre_archivo}"
    )


    # -------------------------------------------------------------------------
    # 12.13. MOSTRAR EL RESULTADO EN PANTALLA
    # -------------------------------------------------------------------------

    print(
        f"[FRED] "
        f"{codigo_serie}: "
        f"{n_filas} observaciones -> "
        f"{os.path.relpath(ruta, RUTA_BASE)}"
    )


# =============================================================================
# PASO 13. EJECUTAR EL PROGRAMA PRINCIPAL
# =============================================================================
#
# Esta condición:
#
#     if __name__ == "__main__":
#
# indica que el bloque siguiente solo se ejecutará cuando este archivo se
# ejecute directamente, por ejemplo:
#
#     python codigo/01_extraccion_api.py
#
# Si el archivo fuera importado desde otro programa, este bloque no se
# ejecutaría automáticamente.
# =============================================================================

if __name__ == "__main__":


    # -------------------------------------------------------------------------
    # 13.1. REGISTRAR EL INICIO DE LA EJECUCIÓN
    # -------------------------------------------------------------------------

    logger.info(
        "=== INICIO 01_extraccion_api ==="
    )


    # Registrar también el periodo utilizado.
    logger.info(
        f"Parametros congelados: "
        f"FECHA_INICIO={FECHA_INICIO} | "
        f"FECHA_CORTE={FECHA_CORTE}"
    )


    # -------------------------------------------------------------------------
    # 13.2. LOCALIZAR Y LEER EL ARCHIVO .env
    # -------------------------------------------------------------------------
    #
    # Se espera una estructura como:
    #
    # proyecto/
    # ├── .env
    # └── codigo/
    #
    # Dentro de .env debe existir:
    #
    # FRED_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    #
    # Guardar la clave fuera del código evita exponerla si el archivo .py se
    # comparte, se entrega al profesor o se sube a un repositorio.
    # -------------------------------------------------------------------------

    ruta_env = os.path.join(
        RUTA_BASE,
        ".env",
    )


    load_dotenv(
        ruta_env
    )


    # Leer la clave cargada desde la variable de entorno.
    clave_fred = os.getenv(
        "FRED_API_KEY"
    )


    # -------------------------------------------------------------------------
    # 13.3. VALIDAR QUE LA CLAVE DE FRED EXISTA
    # -------------------------------------------------------------------------
    #
    # Si no se encuentra la clave, el programa se detiene antes de realizar
    # solicitudes incompletas.
    # -------------------------------------------------------------------------

    if not clave_fred:

        logger.error(
            "No se encontro FRED_API_KEY "
            "en el archivo .env"
        )


        raise SystemExit(
            "No se encontró FRED_API_KEY "
            "en el archivo .env "
            "(ver .env.example)."
        )


    # -------------------------------------------------------------------------
    # 13.4. DESCARGAR LAS SERIES DEL BCRP
    # -------------------------------------------------------------------------
    #
    # Se recorre la lista FUENTES_BCRP.
    #
    # En cada iteración:
    #
    # 1. se descarga una serie;
    # 2. se guarda;
    # 3. se espera PAUSA_SEG segundos;
    # 4. se pasa a la siguiente.
    # -------------------------------------------------------------------------

    for fuente in FUENTES_BCRP:

        extraer_bcrp(
            fuente
        )

        time.sleep(
            PAUSA_SEG
        )


    # -------------------------------------------------------------------------
    # 13.5. DESCARGAR LAS SERIES DE FRED
    # -------------------------------------------------------------------------
    #
    # Se repite el mismo principio para:
    #
    # DFF, DGS2 y DGS10.
    #
    # La clave se pasa a la función, pero nunca se imprime ni se guarda en el
    # log del programa.
    # -------------------------------------------------------------------------

    for codigo in SERIES_FRED:

        extraer_fred(
            codigo,
            clave_fred,
        )

        time.sleep(
            PAUSA_SEG
        )


    # -------------------------------------------------------------------------
    # 13.6. REGISTRAR EL FIN DE LA EJECUCIÓN
    # -------------------------------------------------------------------------

    logger.info(
        "=== FIN 01_extraccion_api ==="
    )


    # -------------------------------------------------------------------------
    # 13.7. INFORMAR AL USUARIO QUE EL PROCESO TERMINÓ
    # -------------------------------------------------------------------------

    print(
        "\nExtracción completada. "
        "Detalle en log_ejecucion.txt"
    )
