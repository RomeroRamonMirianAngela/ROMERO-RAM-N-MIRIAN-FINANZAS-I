# Nombres y Apellidos completos: ROMERO RAMÓN MIRIAN ANGELA
# Código de matrícula: 2024200523C
# Tema y número del temario: Tema 37 - Política monetaria de la Reserva Federal y bonos soberanos peruanos
# Fecha de extracción: 2026-09-24


# =====================================================================
# 04_analisis.R - VERSIÓN FINAL 
# =====================================================================
# Fecha de revisión del análisis: 2026-09-27
# =====================================================================


# =====================================================================
# 1. PAQUETES GENERALES
# =====================================================================

paquetes_generales <- c("here", "tidyverse")
paquetes_faltantes <- paquetes_generales[!paquetes_generales %in% installed.packages()[, "Package"]]
if (length(paquetes_faltantes) > 0) install.packages(paquetes_faltantes)
invisible(lapply(paquetes_generales, library, character.only = TRUE))

# Los paquetes especializados se verifican cerca del análisis que los usa.
asegurar_paquete <- function(paquete) {
  if (!requireNamespace(paquete, quietly = TRUE)) install.packages(paquete)
}

# Georgia se usa en Windows; en otros sistemas se recurre a una fuente genérica.
FUENTE_GRAFICOS <- "sans"
if (.Platform$OS.type == "windows") {
  windowsFonts(Georgia = windowsFont("Georgia"))
  FUENTE_GRAFICOS <- "Georgia"
}


# =====================================================================
# 2. PARÁMETROS, RUTAS Y LECTURA DE LA BASE PROCESADA
# =====================================================================

CODIGO_MATRICULA <- "2024200523C"
RUTA_PROCESADOS <- here::here("datos_procesados", paste0("datos_procesados_", CODIGO_MATRICULA, ".csv"))
RUTA_SALIDAS <- here::here("salidas")
dir.create(RUTA_SALIDAS, showWarnings = FALSE, recursive = TRUE)

# Elimina únicamente salidas antiguas que ya no pertenecen a la versión final.
# No se borra la carpeta /salidas ni archivos vigentes del análisis.
archivos_obsoletos <- c(
  "histogramas.png", "correlaciones_pearson.png", "tabla_correlaciones_spearman.csv",
  "dispersion_bono_vs_embig.png", "dispersion_bono_vs_fed_funds.png",
  "dispersion_bono_vs_tesoro_2a.png", "dispersion_bono_vs_tesoro_10a.png",
  "residuos_vs_ajustados.png", "heterocedasticidad_modelo_final.png",
  "acf_pacf_residuos.png", "tabla_atipicos_iqr.csv",
  "tabla_comparacion_winsorizacion.csv", "tabla_descriptivos.txt",
  paste0("base_analisis_", CODIGO_MATRICULA, ".csv")
)
rutas_obsoletas <- file.path(RUTA_SALIDAS, archivos_obsoletos)
invisible(file.remove(rutas_obsoletas[file.exists(rutas_obsoletas)]))


base <- readr::read_csv(RUTA_PROCESADOS, show_col_types = FALSE) %>% dplyr::mutate(fecha = as.Date(fecha))


# El análisis parte de la base ya depurada por 03_limpieza_datos.py.
columnas_requeridas <- c(
  "fecha", "bono_pe_10a_soles", "bono_pe_10a_soles_w",
  "embig_peru_pbs", "embig_peru_pp", "embig_peru_pp_w",
  "tasa_fondos_federales", "tesoro_2a", "tesoro_10a"
)

columnas_faltantes <- setdiff(columnas_requeridas, names(base))
if (length(columnas_faltantes) > 0) stop("Faltan columnas requeridas: ", paste(columnas_faltantes, collapse = ", "))

variables_finales <- c(
  "bono_pe_10a_soles_w", "embig_peru_pp_w", "tasa_fondos_federales",
  "tesoro_2a", "tesoro_10a"
)

etiquetas_finales <- c(
  bono_pe_10a_soles_w = "Bono soberano PE 10 años (%)",
  embig_peru_pp_w = "EMBIG Perú (p.p.)",
  tasa_fondos_federales = "Tasa de fondos federales (%)",
  tesoro_2a = "Tesoro EE. UU. 2 años (%)",
  tesoro_10a = "Tesoro EE. UU. 10 años (%)"
)

paleta_variables <- c(
  "Bono soberano PE 10 años (%)" = "#2E8B57",
  "EMBIG Perú (p.p.)" = "#66C2A5",
  "Tasa de fondos federales (%)" = "#8DA0CB",
  "Tesoro EE. UU. 2 años (%)" = "#FC8D62",
  "Tesoro EE. UU. 10 años (%)" = "#E78AC3"
)

# La base procesada debería llegar completa; esta validación evita continuar
# silenciosamente si una futura extracción introduce faltantes.
n_faltantes_finales <- sum(is.na(base[, variables_finales]))
if (n_faltantes_finales > 0) warning("La base contiene ", n_faltantes_finales, " valores faltantes en variables finales.")


# =====================================================================
# 3. ESTADÍSTICOS DESCRIPTIVOS ESENCIALES
# =====================================================================
# Para el journal se conserva una tabla compacta: N, media, mediana,
# desviación estándar, mínimo y máximo.

calcular_descriptivos <- function(datos, variable) {
  x <- datos[[variable]]

  tibble::tibble(
    variable = etiquetas_finales[[variable]],
    n = sum(!is.na(x)),
    media = mean(x, na.rm = TRUE),
    mediana = median(x, na.rm = TRUE),
    desviacion_estandar = sd(x, na.rm = TRUE),
    coeficiente_variacion_pct = sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE) * 100,
    minimo = min(x, na.rm = TRUE),
    maximo = max(x, na.rm = TRUE)
  )
}

tabla_descriptivos <- purrr::map_dfr(
  variables_finales,
  ~calcular_descriptivos(base, .x)
) %>%
  dplyr::mutate(
    dplyr::across(where(is.numeric), ~round(.x, 4))
  )

print(tabla_descriptivos)

readr::write_csv(
  tabla_descriptivos,
  file.path(RUTA_SALIDAS, "tabla_descriptivos.csv")
)
# =====================================================================
# 4. EVOLUCIÓN TEMPORAL DE LAS VARIABLES
# =====================================================================
# Una sola figura resume el comportamiento de las cinco series durante
# 2010-2025 y evita multiplicar gráficos innecesarios en el journal.

base_larga <- base %>%
  dplyr::select(fecha, dplyr::all_of(variables_finales)) %>%
  tidyr::pivot_longer(cols = dplyr::all_of(variables_finales), names_to = "variable", values_to = "valor") %>%
  dplyr::mutate(variable = dplyr::recode(variable, !!!etiquetas_finales))

grafico_series <- ggplot2::ggplot(base_larga, ggplot2::aes(x = fecha, y = valor, color = variable)) +
  ggplot2::geom_line(linewidth = 0.5) +
  ggplot2::scale_color_manual(values = paleta_variables) +
  ggplot2::facet_wrap(~variable, scales = "free_y", ncol = 2) +
  ggplot2::labs(
    title = "Evolución diaria de las variables del estudio",
    subtitle = paste("Periodo:", min(base$fecha), "a", max(base$fecha)),
    x = "Fecha", y = "Valor"
  ) +
  ggplot2::theme_minimal(base_size = 12, base_family = FUENTE_GRAFICOS) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 15, hjust = 0.5),
    plot.subtitle = ggplot2::element_text(size = 10.5, hjust = 0.5),
    strip.text = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "none"
  )

ggplot2::ggsave(file.path(RUTA_SALIDAS, "series_tiempo.png"), grafico_series, width = 10, height = 7, dpi = 300)


# =====================================================================
# 5. BOXPLOTS DE LAS VARIABLES FINALES
# =====================================================================
# Los boxplots permiten verificar visualmente la distribución posterior al
# tratamiento realizado en 03_limpieza_datos.py. 

grafico_boxplots <- ggplot2::ggplot(base_larga, ggplot2::aes(x = variable, y = valor, fill = variable)) +
  ggplot2::geom_boxplot(alpha = 0.78, outlier.color = "#8B0000", outlier.size = 1.8) +
  ggplot2::scale_fill_manual(values = paleta_variables) +
  ggplot2::facet_wrap(~variable, scales = "free_y", ncol = 3) +
  ggplot2::labs(
    title = "Diagramas de caja de las variables finales del análisis",
    subtitle = "Variables peruanas tratadas en 03_limpieza_datos.py; sin nuevas transformaciones en R",
    x = NULL, y = "Valor"
  ) +
  ggplot2::theme_minimal(base_size = 12, base_family = FUENTE_GRAFICOS) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 15, hjust = 0.5),
    plot.subtitle = ggplot2::element_text(size = 10.5, hjust = 0.5),
    axis.text.x = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold", size = 10),
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "none"
  )

ggplot2::ggsave(file.path(RUTA_SALIDAS, "boxplots_finales.png"), grafico_boxplots, width = 11, height = 7, dpi = 300)


# =====================================================================
# 6. DISPERSIÓN CONJUNTA: BONO PERUANO VS. VARIABLES EXPLICATIVAS
# =====================================================================
# Las cuatro relaciones bivariadas se presentan en una sola figura mediante
# facetas. Así se conserva la evidencia visual sin ocupar cuatro figuras
# separadas en el journal.

etiquetas_dispersion <- c(
  embig_peru_pp_w = "EMBIG Perú (p.p.)",
  tasa_fondos_federales = "Tasa de fondos federales (%)",
  tesoro_2a = "Tesoro EE. UU. 2 años (%)",
  tesoro_10a = "Tesoro EE. UU. 10 años (%)"
)

paleta_dispersion <- c(
  "EMBIG Perú (p.p.)" = "#2E86AB",
  "Tasa de fondos federales (%)" = "#E76F51",
  "Tesoro EE. UU. 2 años (%)" = "#6A4C93",
  "Tesoro EE. UU. 10 años (%)" = "#F4A261"
)

base_dispersion <- base %>%
  dplyr::select(bono_pe_10a_soles_w, dplyr::all_of(names(etiquetas_dispersion))) %>%
  tidyr::pivot_longer(
    cols = dplyr::all_of(names(etiquetas_dispersion)),
    names_to = "variable_x",
    values_to = "valor_x"
  ) %>%
  dplyr::mutate(variable_x = dplyr::recode(variable_x, !!!etiquetas_dispersion))

grafico_dispersion_conjunta <- ggplot2::ggplot(
  base_dispersion,
  ggplot2::aes(x = valor_x, y = bono_pe_10a_soles_w, color = variable_x, fill = variable_x)
) +
  ggplot2::geom_point(alpha = 0.38, size = 1.25) +
  ggplot2::geom_smooth(method = "lm", formula = y ~ x, se = TRUE, linewidth = 0.85, alpha = 0.18) +
  ggplot2::scale_color_manual(values = paleta_dispersion) +
  ggplot2::scale_fill_manual(values = paleta_dispersion) +
  ggplot2::facet_wrap(~variable_x, scales = "free_x", ncol = 2) +
  ggplot2::labs(
    title = "Bono soberano peruano y condiciones financieras externas",
    subtitle = "Relaciones bivariadas con ajuste lineal e intervalo de confianza al 95%",
    x = "Variable explicativa",
    y = "Bono soberano PE 10 años (%)"
  ) +
  ggplot2::theme_minimal(base_size = 12, base_family = FUENTE_GRAFICOS) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 15, hjust = 0.5),
    plot.subtitle = ggplot2::element_text(size = 10.5, hjust = 0.5),
    strip.text = ggplot2::element_text(face = "bold", size = 10),
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "none"
  )

ggplot2::ggsave(file.path(RUTA_SALIDAS, "dispersion_conjunta.png"), grafico_dispersion_conjunta, width = 11, height = 8, dpi = 300)


# =====================================================================
# 7. CORRELACIONES DE PEARSON
# =====================================================================
# Pearson funciona como exploración bivariada inicial.

matriz_pearson <- base %>%
  dplyr::select(dplyr::all_of(variables_finales)) %>%
  stats::cor(use = "complete.obs", method = "pearson")

colnames(matriz_pearson) <- etiquetas_finales[variables_finales]
rownames(matriz_pearson) <- etiquetas_finales[variables_finales]

readr::write_csv(as.data.frame(round(matriz_pearson, 4)) %>% tibble::rownames_to_column("variable"),
                 file.path(RUTA_SALIDAS, "tabla_correlaciones_pearson.csv"))

#..............................................................................
# PAQUETE UTILIZADO PARA VISUALIZAR LA MATRIZ DE CORRELACIONES

if (!requireNamespace("corrplot", quietly = TRUE)) install.packages("corrplot")

#..............................................................................
# GRÁFICO DE CORRELACIONES DE PEARSON
# Esta figura resume visualmente la dirección y magnitud de las asociaciones
# lineales entre las variables finales utilizadas en el análisis.

colores_corr <- colorRampPalette(
  c("#B22222", "#F7F7F7", "#1E3A8A")
)(200)

png(
  file.path(RUTA_SALIDAS, "correlaciones_pearson.png"),
  width = 1800,
  height = 1800,
  res = 220
)

par(family = "Georgia")

corrplot::corrplot(
  matriz_pearson,
  method = "color",
  type = "upper",
  col = colores_corr,
  addCoef.col = "black",
  number.cex = 0.9,
  number.font = 2,
  tl.col = "black",
  tl.cex = 1,
  tl.srt = 45,
  diag = FALSE,
  cl.cex = 0.9,
  mar = c(0, 0, 3, 0),
  title = "Matriz de correlaciones de Pearson"
)

dev.off()


# =====================================================================
# 8. PRUEBAS DE ESTACIONARIEDAD: ADF Y KPSS
# =====================================================================
# ADF: H0 = raíz unitaria. KPSS: H0 = estacionariedad en nivel.
# Se usan juntas porque sus hipótesis nulas son complementarias.

asegurar_paquete("tseries")

probar_estacionariedad <- function(x, nombre_variable) {
  x <- stats::na.omit(x)
  adf <- tseries::adf.test(x)
  kpss <- tseries::kpss.test(x, null = "Level")

  conclusion <- dplyr::case_when(
    adf$p.value < 0.05 & kpss$p.value >= 0.05 ~ "Evidencia favorable a estacionariedad en nivel",
    adf$p.value >= 0.05 & kpss$p.value < 0.05 ~ "Evidencia favorable a no estacionariedad",
    TRUE ~ "Resultados mixtos: revisar antes de interpretar el modelo en niveles"
  )

  tibble::tibble(
    variable = etiquetas_finales[[nombre_variable]],
    adf_estadistico = unname(adf$statistic),
    adf_p_valor = adf$p.value,
    kpss_estadistico = unname(kpss$statistic),
    kpss_p_valor = kpss$p.value,
    conclusion = conclusion
  )
}

tabla_estacionariedad <- purrr::map_dfr(
  variables_finales,
  ~probar_estacionariedad(base[[.x]], .x)
) %>% dplyr::mutate(dplyr::across(where(is.numeric), ~round(.x, 4)))

print(tabla_estacionariedad, width = Inf)
readr::write_csv(tabla_estacionariedad, file.path(RUTA_SALIDAS, "tabla_estacionariedad_adf_kpss.csv"))

if (any(grepl("no estacionariedad|Resultados mixtos", tabla_estacionariedad$conclusion))) {
  warning("ADF/KPSS no respaldan de forma uniforme la estacionariedad de todas las series. Revise esta tabla antes de interpretar causalmente el modelo en niveles.")
}


# =====================================================================
# 9. CORRELACIONES PARCIALES
# =====================================================================
# Miden la relación entre el bono y cada factor manteniendo constantes las
# demás variables externas. Se aplica ajuste de Holm por comparaciones múltiples.

asegurar_paquete("ppcor")

variable_endogena <- "bono_pe_10a_soles_w"
variables_exogenas <- c("embig_peru_pp_w", "tasa_fondos_federales", "tesoro_2a", "tesoro_10a")
etiquetas_exogenas <- etiquetas_finales[variables_exogenas]

calcular_cor_parcial <- function(exogena) {
  controles <- setdiff(variables_exogenas, exogena)
  datos <- base %>% dplyr::select(dplyr::all_of(c(variable_endogena, exogena, controles))) %>% tidyr::drop_na()
  prueba <- ppcor::pcor.test(datos[[variable_endogena]], datos[[exogena]], datos[, controles], method = "pearson")

  tibble::tibble(
    variable = etiquetas_exogenas[[exogena]],
    correlacion_parcial = unname(prueba$estimate),
    estadistico_t = unname(prueba$statistic),
    p_valor = prueba$p.value,
    n = nrow(datos)
  )
}

tabla_correlaciones_parciales <- purrr::map_dfr(variables_exogenas, calcular_cor_parcial) %>%
  dplyr::mutate(
    p_valor_holm = stats::p.adjust(p_valor, method = "holm"),
    significativo_5pct = ifelse(p_valor_holm < 0.05, "Sí", "No"),
    dplyr::across(c(correlacion_parcial, estadistico_t, p_valor, p_valor_holm), ~round(.x, 5))
  )

print(tabla_correlaciones_parciales, width = Inf)
readr::write_csv(tabla_correlaciones_parciales, file.path(RUTA_SALIDAS, "tabla_correlaciones_parciales.csv"))


# =====================================================================
# 10. MODELO ECONOMÉTRICO Y MULTICOLINEALIDAD
# =====================================================================
# Primero se estima la parametrización original únicamente para diagnosticar
# multicolinealidad. Después se representa Tesoro 2A mediante el spread
# Tesoro 2A - Fed funds, lo cual conserva los valores ajustados del modelo
# pero reduce la dependencia lineal entre regresores.

asegurar_paquete("car")

modelo_original <- stats::lm(
  bono_pe_10a_soles_w ~ embig_peru_pp_w + tasa_fondos_federales + tesoro_2a + tesoro_10a,
  data = base
)

vif_original <- car::vif(modelo_original)

base <- base %>% dplyr::mutate(spread_tesoro2_fed = tesoro_2a - tasa_fondos_federales)

modelo <- stats::lm(
  bono_pe_10a_soles_w ~ embig_peru_pp_w + tasa_fondos_federales + spread_tesoro2_fed + tesoro_10a,
  data = base
)

vif_final <- car::vif(modelo)

tabla_vif <- dplyr::bind_rows(
  tibble::tibble(modelo = "Parametrización original", variable = names(vif_original), vif = as.numeric(vif_original)),
  tibble::tibble(modelo = "Parametrización final", variable = names(vif_final), vif = as.numeric(vif_final))
) %>% dplyr::mutate(vif = round(vif, 4))

print(tabla_vif)
readr::write_csv(tabla_vif, file.path(RUTA_SALIDAS, "tabla_vif.csv"))


# =====================================================================
# 11. DIAGNÓSTICOS DEL MODELO FINAL
# =====================================================================
# Se concentran en una sola tabla para el journal: Breusch-Pagan para
# heterocedasticidad, Breusch-Godfrey para autocorrelación y Jarque-Bera
# para normalidad de residuos.

asegurar_paquete("lmtest")
asegurar_paquete("tseries")

prueba_bp <- lmtest::bptest(modelo)
prueba_bg1 <- lmtest::bgtest(modelo, order = 1)
prueba_bg5 <- lmtest::bgtest(modelo, order = 5)
prueba_jb <- tseries::jarque.bera.test(stats::residuals(modelo))

tabla_diagnosticos <- tibble::tibble(
  prueba = c("Breusch-Pagan", "Breusch-Godfrey (1 rezago)", "Breusch-Godfrey (5 rezagos)", "Jarque-Bera"),
  hipotesis_nula = c(
    "Homocedasticidad",
    "Ausencia de autocorrelación hasta rezago 1",
    "Ausencia de autocorrelación hasta rezago 5",
    "Normalidad de los residuos"
  ),
  estadistico = c(unname(prueba_bp$statistic), unname(prueba_bg1$statistic), unname(prueba_bg5$statistic), unname(prueba_jb$statistic)),
  p_valor = c(prueba_bp$p.value, prueba_bg1$p.value, prueba_bg5$p.value, prueba_jb$p.value)
) %>%
  dplyr::mutate(
    decision_5pct = ifelse(p_valor < 0.05, "Rechazar H0", "No rechazar H0"),
    estadistico = round(estadistico, 4),
    p_valor = signif(p_valor, 5)
  )

print(tabla_diagnosticos, width = Inf)
readr::write_csv(tabla_diagnosticos, file.path(RUTA_SALIDAS, "tabla_diagnosticos_modelo.csv"))


# =====================================================================
# 12. INFERENCIA ROBUSTA NEWEY-WEST (HAC)
# =====================================================================
# Newey-West corrige los errores estándar frente a heterocedasticidad y
# autocorrelación. Se usa lag = 5 para cubrir dependencia aproximada de una
# semana hábil en los datos diarios. Los coeficientes del modelo no cambian;
# cambian los errores estándar y, por tanto, la inferencia.

asegurar_paquete("sandwich")

matriz_hac <- sandwich::NeweyWest(modelo, lag = 5, prewhite = FALSE, adjust = TRUE)
modelo_hac <- lmtest::coeftest(modelo, vcov. = matriz_hac)

etiquetas_modelo <- c(
  "(Intercept)" = "Constante",
  embig_peru_pp_w = "EMBIG Perú",
  tasa_fondos_federales = "Tasa de fondos federales",
  spread_tesoro2_fed = "Spread Tesoro 2A - Fed",
  tesoro_10a = "Tesoro EE. UU. 10 años"
)

tabla_modelo_hac <- tibble::tibble(
  termino = rownames(modelo_hac),
  coeficiente = modelo_hac[, 1],
  error_estandar_hac = modelo_hac[, 2],
  estadistico_t = modelo_hac[, 3],
  p_valor = modelo_hac[, 4]
) %>%
  dplyr::mutate(
    variable = dplyr::recode(termino, !!!etiquetas_modelo),
    significancia = dplyr::case_when(
      p_valor < 0.01 ~ "***",
      p_valor < 0.05 ~ "**",
      p_valor < 0.10 ~ "*",
      TRUE ~ ""
    ),
    dplyr::across(c(coeficiente, error_estandar_hac, estadistico_t), ~round(.x, 5)),
    p_valor = signif(p_valor, 5)
  ) %>%
  dplyr::select(variable, coeficiente, error_estandar_hac, estadistico_t, p_valor, significancia)

resumen_modelo <- summary(modelo)
tabla_ajuste_modelo <- tibble::tibble(
  n = stats::nobs(modelo),
  r_cuadrado = resumen_modelo$r.squared,
  r_cuadrado_ajustado = resumen_modelo$adj.r.squared,
  lag_newey_west = 5,
  vif_maximo_final = max(vif_final)
) %>% dplyr::mutate(dplyr::across(where(is.numeric), ~round(.x, 5)))

print(tabla_modelo_hac, width = Inf)
print(tabla_ajuste_modelo)
readr::write_csv(tabla_modelo_hac, file.path(RUTA_SALIDAS, "tabla_modelo_final_hac.csv"))
readr::write_csv(tabla_ajuste_modelo, file.path(RUTA_SALIDAS, "tabla_ajuste_modelo.csv"))


# =====================================================================
# 13. SENSIBILIDAD DEL BONO A LA FED A TRAVÉS DEL TIEMPO
# =====================================================================
ventana <- 252
paso <- 5

# Se ordena la base por fecha y se utilizan únicamente observaciones completas
# para las variables que forman parte del modelo móvil.
base_ordenada <- base %>%
  dplyr::arrange(fecha) %>%
  tidyr::drop_na(
    bono_pe_10a_soles_w,
    embig_peru_pp_w,
    tasa_fondos_federales,
    spread_tesoro2_fed,
    tesoro_10a
  )

n_obs <- nrow(base_ordenada)

# Verifica que existan suficientes observaciones para construir al menos
# una ventana móvil de 252 datos.
if (n_obs < ventana) {
  stop("No hay suficientes observaciones para la regresión móvil de 252 datos.")
}

# Se avanza cada cinco observaciones para reducir el costo computacional
# sin perder la evolución temporal general del coeficiente.
indices_inicio <- seq(
  1,
  n_obs - ventana + 1,
  by = paso
)


# ---------------------------------------------------------------------
# FUNCIÓN PARA ESTIMAR EL COEFICIENTE MÓVIL DE FED FUNDS
# ---------------------------------------------------------------------

calcular_coef_movil <- function(i) {

  # Selecciona las 252 observaciones correspondientes a cada ventana.
  datos_ventana <- base_ordenada[
    i:(i + ventana - 1),
  ]

  # Estima el mismo modelo utilizado en el análisis econométrico final.
  modelo_ventana <- stats::lm(
    bono_pe_10a_soles_w ~
      embig_peru_pp_w +
      tasa_fondos_federales +
      spread_tesoro2_fed +
      tesoro_10a,
    data = datos_ventana
  )

  # tryCatch permite continuar aunque una ventana particular no pueda
  # producir correctamente la matriz HAC o el coeficiente de Fed funds.
  resultado <- tryCatch({

    # Primero se comprueba que el coeficiente exista y sea estimable.
    coeficientes_modelo <- stats::coef(modelo_ventana)

    if (
      !"tasa_fondos_federales" %in% names(coeficientes_modelo) ||
      is.na(coeficientes_modelo["tasa_fondos_federales"])
    ) {

      tibble::tibble(
        fecha = datos_ventana$fecha[ventana],
        coef_fed = NA_real_,
        error_estandar_hac = NA_real_,
        ic_inferior = NA_real_,
        ic_superior = NA_real_,
        estimable = FALSE
      )

    } else {

      # Matriz de varianzas y covarianzas robusta Newey-West.
      vcov_ventana <- sandwich::NeweyWest(
        modelo_ventana,
        lag = 5,
        prewhite = FALSE,
        adjust = TRUE
      )

      # Coeficientes con errores estándar HAC.
      prueba_ventana <- lmtest::coeftest(
        modelo_ventana,
        vcov. = vcov_ventana
      )

      # En algunas ventanas coeftest puede excluir un coeficiente que no
      # sea identificable. Se verifica antes de intentar extraerlo.
      if (!"tasa_fondos_federales" %in% rownames(prueba_ventana)) {

        tibble::tibble(
          fecha = datos_ventana$fecha[ventana],
          coef_fed = NA_real_,
          error_estandar_hac = NA_real_,
          ic_inferior = NA_real_,
          ic_superior = NA_real_,
          estimable = FALSE
        )

      } else {

        coef_fed <- unname(
          prueba_ventana["tasa_fondos_federales", 1]
        )

        se_fed <- unname(
          prueba_ventana["tasa_fondos_federales", 2]
        )

        # Si alguno de los resultados no es finito, la ventana también
        # se considera no estimable.
        if (!is.finite(coef_fed) || !is.finite(se_fed)) {

          tibble::tibble(
            fecha = datos_ventana$fecha[ventana],
            coef_fed = NA_real_,
            error_estandar_hac = NA_real_,
            ic_inferior = NA_real_,
            ic_superior = NA_real_,
            estimable = FALSE
          )

        } else {

          tibble::tibble(
            fecha = datos_ventana$fecha[ventana],
            coef_fed = coef_fed,
            error_estandar_hac = se_fed,
            ic_inferior = coef_fed - 1.96 * se_fed,
            ic_superior = coef_fed + 1.96 * se_fed,
            estimable = TRUE
          )
        }
      }
    }

  }, error = function(e) {

    # Si ocurre un problema numérico dentro de una ventana particular,
    # se registra como no estimable y el análisis continúa.
    tibble::tibble(
      fecha = datos_ventana$fecha[ventana],
      coef_fed = NA_real_,
      error_estandar_hac = NA_real_,
      ic_inferior = NA_real_,
      ic_superior = NA_real_,
      estimable = FALSE
    )
  })

  resultado
}


# ---------------------------------------------------------------------
# ESTIMACIÓN DE TODAS LAS VENTANAS MÓVILES
# ---------------------------------------------------------------------

rolling_coef_fed <- purrr::map_dfr(
  indices_inicio,
  calcular_coef_movil
)

# La tabla completa conserva también las ventanas no estimables.
readr::write_csv(
  rolling_coef_fed,
  file.path(
    RUTA_SALIDAS,
    "tabla_coeficiente_movil_fed.csv"
  )
)

# Se informa cuántas ventanas pudieron y no pudieron estimarse.
cat(
  "\nRegresión móvil de la Fed:\n",
  "Ventanas totales:", nrow(rolling_coef_fed), "\n",
  "Ventanas estimables:", sum(rolling_coef_fed$estimable), "\n",
  "Ventanas no estimables:", sum(!rolling_coef_fed$estimable), "\n"
)


# ---------------------------------------------------------------------
# BASE UTILIZADA EXCLUSIVAMENTE PARA EL GRÁFICO
# ---------------------------------------------------------------------
# Las ventanas no estimables permanecen en el CSV para trazabilidad,
# pero no se utilizan al construir la figura.

rolling_coef_fed_grafico <- rolling_coef_fed %>%
  dplyr::filter(
    estimable,
    is.finite(coef_fed),
    is.finite(ic_inferior),
    is.finite(ic_superior)
  )

if (nrow(rolling_coef_fed_grafico) == 0) {
  stop("Ninguna ventana móvil produjo un coeficiente estimable para Fed funds.")
}


# ---------------------------------------------------------------------
# GRÁFICO DEL COEFICIENTE MÓVIL
# ---------------------------------------------------------------------

grafico_coef_movil_fed <- ggplot2::ggplot(
  rolling_coef_fed_grafico,
  ggplot2::aes(
    x = fecha,
    y = coef_fed
  )
) +
  ggplot2::geom_ribbon(
    ggplot2::aes(
      ymin = ic_inferior,
      ymax = ic_superior
    ),
    alpha = 0.20
  ) +
  ggplot2::geom_line(
    linewidth = 0.8
  ) +
  ggplot2::geom_hline(
    yintercept = 0,
    linetype = "dashed",
    linewidth = 0.7
  ) +
  ggplot2::labs(
    title = "Sensibilidad del bono peruano a la tasa de la Fed a través del tiempo",
    subtitle = "Coeficiente móvil de Fed funds; ventana de 252 observaciones e intervalos HAC al 95%",
    x = "Fecha",
    y = "Coeficiente de tasa de fondos federales"
  ) +
  ggplot2::theme_minimal(
    base_size = 12,
    base_family = FUENTE_GRAFICOS
  ) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(
      face = "bold",
      size = 14,
      hjust = 0.5
    ),
    plot.subtitle = ggplot2::element_text(
      size = 10,
      hjust = 0.5
    ),
    panel.grid.minor = ggplot2::element_blank()
  )


# Guarda la figura final.
ggplot2::ggsave(
  file.path(
    RUTA_SALIDAS,
    "coeficiente_movil_fed.png"
  ),
  grafico_coef_movil_fed,
  width = 10,
  height = 6,
  dpi = 300
)
# =====================================================================
# 14. IMPORTANCIA RELATIVA DE LOS REGRESORES: MÉTODO LMG
# =====================================================================
# Esta descomposición muestra cómo se reparte el R2 explicado entre los
# regresores del modelo final. Es un complemento descriptivo del modelo;
# no sustituye la interpretación de coeficientes ni la inferencia HAC.

asegurar_paquete("relaimpo")

importancia_relativa <- relaimpo::calc.relimp(modelo, type = "lmg", rela = TRUE)

tabla_importancia <- tibble::tibble(
  variable = names(importancia_relativa$lmg),
  importancia_pct = as.numeric(importancia_relativa$lmg) * 100
) %>%
  dplyr::mutate(
    variable = dplyr::recode(variable, !!!etiquetas_modelo),
    importancia_pct = round(importancia_pct, 2)
  ) %>%
  dplyr::arrange(dplyr::desc(importancia_pct))

print(tabla_importancia)
readr::write_csv(tabla_importancia, file.path(RUTA_SALIDAS, "tabla_importancia_relativa.csv"))

grafico_importancia <- ggplot2::ggplot(
  tabla_importancia,
  ggplot2::aes(x = reorder(variable, importancia_pct), y = importancia_pct)
) +
  ggplot2::geom_col(width = 0.65) +
  ggplot2::geom_text(ggplot2::aes(label = paste0(importancia_pct, "%")), hjust = -0.15, family = FUENTE_GRAFICOS) +
  ggplot2::coord_flip(clip = "off") +
  ggplot2::scale_y_continuous(limits = c(0, max(tabla_importancia$importancia_pct) * 1.20)) +
  ggplot2::labs(
    title = "Importancia relativa de las variables del modelo",
    subtitle = paste0("Descomposición LMG del R² = ", round(resumen_modelo$r.squared * 100, 1), "%"),
    x = NULL, y = "% del R² explicado"
  ) +
  ggplot2::theme_minimal(base_size = 12, base_family = FUENTE_GRAFICOS) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14, hjust = 0.5),
    plot.subtitle = ggplot2::element_text(size = 10, hjust = 0.5),
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_blank()
  )

ggplot2::ggsave(file.path(RUTA_SALIDAS, "importancia_relativa_variables.png"), grafico_importancia, width = 9, height = 5.5, dpi = 300)


# =====================================================================
# 15. INFORMACIÓN DE SESIÓN PARA REPRODUCIBILIDAD
# =====================================================================

capture.output(sessionInfo(), file = file.path(RUTA_SALIDAS, "sessionInfo_R.txt"))

cat("\n============================================================\n")
cat("ANÁLISIS FINALIZADO CORRECTAMENTE\n")
cat("============================================================\n")
cat("Observaciones analizadas:", nrow(base), "\n")
cat("Rango temporal:", as.character(min(base$fecha)), "a", as.character(max(base$fecha)), "\n")
cat("R² del modelo final:", round(resumen_modelo$r.squared, 4), "\n")
cat("R² ajustado:", round(resumen_modelo$adj.r.squared, 4), "\n")
cat("Resultados guardados en:", RUTA_SALIDAS, "\n")
