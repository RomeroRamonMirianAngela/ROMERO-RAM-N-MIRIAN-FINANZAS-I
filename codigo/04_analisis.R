# =====================================================================
#                       DATOS GENERALES 
# =====================================================================
# Nombres y Apellidos completos: ROMERO RAMÓN MIRIAN ANGELA
# Código de matrícula: 2024200523C
# Tema y número del temario: Tema 37 - Política monetaria de la Reserva Federal y bonos soberanos peruanos
# Fecha de extracción: 2026-09-24

# =====================================================================
# 04_analisis.R
# =====================================================================
# Fecha de análisis: 2026-09-25

# =====================================================================
#               ANÁLISIS ESTADÍSTICO DESCRIPTIVO
# =====================================================================


#..............................................................................
# PAQUETES GENERALES DEL SCRIPT

paquetes_generales <- c("here", "tidyverse")
paquetes_faltantes <- paquetes_generales[!paquetes_generales %in% installed.packages()[, "Package"]]
if (length(paquetes_faltantes) > 0) install.packages(paquetes_faltantes)
invisible(lapply(paquetes_generales, library, character.only = TRUE))

# Registra Georgia para mantener la misma tipografía en todos los gráficos.
# La condición evita errores si el script se ejecuta en un sistema distinto de Windows.
if (.Platform$OS.type == "windows") windowsFonts(Georgia = windowsFont("Georgia"))
#..............................................................................


#..............................................................................
# PARÁMETROS Y RUTAS DEL PROYECTO

CODIGO_MATRICULA <- "2024200523C"

# Ruta del archivo procesado generado previamente por 03_limpieza_datos.py.
RUTA_PROCESADOS <- here("datos_procesados", paste0("datos_procesados_", CODIGO_MATRICULA, ".csv"))

# Carpeta donde se guardarán tablas, gráficos y resultados.
RUTA_SALIDAS <- here("salidas")

# Crea la carpeta /salidas en caso de que todavía no exista.
dir.create(RUTA_SALIDAS, showWarnings = FALSE, recursive = TRUE)
#..............................................................................


#..............................................................................
# LECTURA DE LA BASE PROCESADA

base <- read_csv(RUTA_PROCESADOS, show_col_types = FALSE) %>%
  mutate(fecha = as.Date(fecha))

View(base)
#..............................................................................


#..............................................................................
# VALIDACIÓN DE LA BASE

columnas_requeridas <- c(
  "fecha", "bono_pe_10a_soles", "embig_peru_pbs",
  "tasa_fondos_federales", "tesoro_2a", "tesoro_10a"
)

columnas_faltantes <- setdiff(columnas_requeridas, names(base))

# Si falta alguna variable, el programa se detiene para evitar resultados incorrectos.
if (length(columnas_faltantes) > 0) stop("Faltan columnas requeridas: ", paste(columnas_faltantes, collapse = ", "))

# Muestra la estructura de las variables.
str(base)
#..............................................................................


#..............................................................................
# CONVERSIÓN DEL EMBIG PERÚ A PUNTOS PORCENTUALES
# La relación utilizada es: 100 puntos básicos = 1 punto porcentual

base <- base %>%
  mutate(embig_peru_pp = embig_peru_pbs / 100)
#..............................................................................



#----------------------------------------------------------------------------
#                       WINSORIZACIÓN
#----------------------------------------------------------------------------

# 1. VARIABLES UTILIZADAS EN EL ANÁLISIS

# Variables originales que serán analizadas antes de la winsorización.
variables_originales <- c(
  "bono_pe_10a_soles", "embig_peru_pp",
  "tasa_fondos_federales", "tesoro_2a", "tesoro_10a"
)

# Solamente estas dos variables serán winsorizadas.
variables_winsorizar <- c("bono_pe_10a_soles", "embig_peru_pp")


# 2. FUNCIÓN PARA IDENTIFICAR VALORES ATÍPICOS CON EL CRITERIO IQR

diagnosticar_atipicos <- function(x, nombre_variable) {

  q1 <- quantile(x, 0.25, na.rm = TRUE, names = FALSE)
  q3 <- quantile(x, 0.75, na.rm = TRUE, names = FALSE)
  iqr <- q3 - q1

  limite_inferior <- q1 - 1.5 * iqr
  limite_superior <- q3 + 1.5 * iqr

  n_validos <- sum(!is.na(x))
  n_atipicos <- sum(x < limite_inferior | x > limite_superior, na.rm = TRUE)
  porcentaje_atipicos <- ifelse(n_validos > 0, n_atipicos / n_validos * 100, NA_real_)

  tibble(
    variable = nombre_variable,
    n = n_validos,
    q1 = q1,
    q3 = q3,
    iqr = iqr,
    limite_inferior = limite_inferior,
    limite_superior = limite_superior,
    minimo_observado = min(x, na.rm = TRUE),
    maximo_observado = max(x, na.rm = TRUE),
    n_atipicos = n_atipicos,
    porcentaje_atipicos = porcentaje_atipicos
  )
}


# 3. DIAGNÓSTICO DE ATÍPICOS EN LAS VARIABLES PERUANAS

diagnostico_atipicos <- bind_rows(
  diagnosticar_atipicos(base$bono_pe_10a_soles, "bono_pe_10a_soles"),
  diagnosticar_atipicos(base$embig_peru_pp, "embig_peru_pp")
)

diagnostico_atipicos <- diagnostico_atipicos %>%
  mutate(across(where(is.numeric), ~round(.x, 4)))

write_csv(diagnostico_atipicos, file.path(RUTA_SALIDAS, "tabla_atipicos_iqr.csv"))


# 4. FUNCIÓN DE WINSORIZACIÓN MEDIANTE LÍMITES IQR

winsorizar_iqr <- function(x) {

  q1 <- quantile(x, 0.25, na.rm = TRUE, names = FALSE)
  q3 <- quantile(x, 0.75, na.rm = TRUE, names = FALSE)
  iqr <- q3 - q1

  limite_inferior <- q1 - 1.5 * iqr
  limite_superior <- q3 + 1.5 * iqr
  return(pmin(pmax(x, limite_inferior), limite_superior))
}


# 5. WINSORIZACIÓN DE LAS DOS VARIABLES PERUANAS

base <- base %>%
  mutate(
    bono_pe_10a_soles_w = winsorizar_iqr(bono_pe_10a_soles),
    embig_peru_pp_w = winsorizar_iqr(embig_peru_pp)
  )


# 6. TABLA COMPARATIVA ANTES Y DESPUÉS DE LA WINSORIZACIÓN

# [CORREGIDO] n_modificados_bono / n_modificados_embig no existían: se
# calculan aquí como el número de observaciones que la winsorización alteró.
n_modificados_bono <- sum(base$bono_pe_10a_soles != base$bono_pe_10a_soles_w, na.rm = TRUE)
n_modificados_embig <- sum(base$embig_peru_pp != base$embig_peru_pp_w, na.rm = TRUE)

comparacion_winsorizacion <- tibble(
  variable = c("Bono soberano Perú 10 años", "EMBIG Perú"),
  n_modificados = c(n_modificados_bono, n_modificados_embig),
  media_original = c(mean(base$bono_pe_10a_soles, na.rm = TRUE), mean(base$embig_peru_pp, na.rm = TRUE)),
  media_winsorizada = c(mean(base$bono_pe_10a_soles_w, na.rm = TRUE), mean(base$embig_peru_pp_w, na.rm = TRUE)),
  mediana_original = c(median(base$bono_pe_10a_soles, na.rm = TRUE), median(base$embig_peru_pp, na.rm = TRUE)),
  mediana_winsorizada = c(median(base$bono_pe_10a_soles_w, na.rm = TRUE), median(base$embig_peru_pp_w, na.rm = TRUE)),
  de_original = c(sd(base$bono_pe_10a_soles, na.rm = TRUE), sd(base$embig_peru_pp, na.rm = TRUE)),
  de_winsorizada = c(sd(base$bono_pe_10a_soles_w, na.rm = TRUE), sd(base$embig_peru_pp_w, na.rm = TRUE)),
  minimo_original = c(min(base$bono_pe_10a_soles, na.rm = TRUE), min(base$embig_peru_pp, na.rm = TRUE)),
  minimo_winsorizado = c(min(base$bono_pe_10a_soles_w, na.rm = TRUE), min(base$embig_peru_pp_w, na.rm = TRUE)),
  maximo_original = c(max(base$bono_pe_10a_soles, na.rm = TRUE), max(base$embig_peru_pp, na.rm = TRUE)),
  maximo_winsorizado = c(max(base$bono_pe_10a_soles_w, na.rm = TRUE), max(base$embig_peru_pp_w, na.rm = TRUE))
) %>%
  mutate(across(where(is.numeric), ~round(.x, 4)))

print(comparacion_winsorizacion)
write_csv(comparacion_winsorizacion, file.path(RUTA_SALIDAS, "tabla_comparacion_winsorizacion.csv"))


# 7. VARIABLES FINALES PARA EL ANÁLISIS ESTADÍSTICO

variables_finales <- c(
  "bono_pe_10a_soles_w", "embig_peru_pp_w", "tasa_fondos_federales",
  "tesoro_2a", "tesoro_10a"
)

# Etiquetas legibles para tablas y gráficos.
etiquetas_finales <- c(
  bono_pe_10a_soles_w = "Bono soberano PE 10 años (%)",
  embig_peru_pp_w = "EMBIG Perú (p.p.)",
  tasa_fondos_federales = "Tasa de fondos federales (%)",
  tesoro_2a = "Tesoro EE. UU. 2 años (%)",
  tesoro_10a = "Tesoro EE. UU. 10 años (%)"
)

# Paleta de colores fija por variable, reutilizada en todos los
# gráficos (series, histogramas, boxplots) para que cada variable se
# identifique siempre con el mismo color y los gráficos no salgan monocromos.
paleta_variables <- c(
  "Bono soberano PE 10 años (%)" = "#2E8B57",
  "EMBIG Perú (p.p.)" = "#66C2A5",
  "Tasa de fondos federales (%)" = "#8DA0CB",
  "Tesoro EE. UU. 2 años (%)" = "#FC8D62",
  "Tesoro EE. UU. 10 años (%)" = "#E78AC3"
)


#..............................................................................
# PAQUETES UTILIZADOS EN LOS ESTADÍSTICOS DESCRIPTIVOS
# moments calcula asimetría y curtosis; knitr permite exportar una tabla legible.
if (!requireNamespace("moments", quietly = TRUE)) install.packages("moments")
if (!requireNamespace("knitr", quietly = TRUE)) install.packages("knitr")

# FUNCIÓN PARA CALCULAR ESTADÍSTICOS DESCRIPTIVOS

calcular_descriptivos <- function(datos, variables) {

  resultado <- purrr::map_dfr(variables, function(variable) {

    x <- datos[[variable]]

    q1 <- quantile(x, 0.25, na.rm = TRUE, names = FALSE)
    q3 <- quantile(x, 0.75, na.rm = TRUE, names = FALSE)

    tibble(
      variable = variable,
      n = sum(!is.na(x)),
      faltantes = sum(is.na(x)),
      media = mean(x, na.rm = TRUE),
      mediana = median(x, na.rm = TRUE),
      de = sd(x, na.rm = TRUE),
      cv_pct = ifelse(abs(mean(x, na.rm = TRUE)) > .Machine$double.eps, sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE) * 100, NA_real_),
      mad = mad(x, na.rm = TRUE),
      minimo = min(x, na.rm = TRUE),
      p01 = quantile(x, 0.01, na.rm = TRUE, names = FALSE),
      q1 = q1,
      q3 = q3,
      p99 = quantile(x, 0.99, na.rm = TRUE, names = FALSE),
      maximo = max(x, na.rm = TRUE),
      rango = max(x, na.rm = TRUE) - min(x, na.rm = TRUE),
      iqr = q3 - q1,
      asimetria = moments::skewness(x, na.rm = TRUE),
      curtosis_exceso = moments::kurtosis(x, na.rm = TRUE) - 3
    )
  })

  resultado <- resultado %>%
    mutate(across(where(is.numeric), ~round(.x, 4)))

  return(resultado)
}


descriptivos <- calcular_descriptivos(base, variables_finales)

descriptivos <- descriptivos %>%
  mutate(descripcion = dplyr::recode(variable, !!!etiquetas_finales), .after = variable)

cat("\n============================================================\n")
cat("ESTADÍSTICOS DESCRIPTIVOS\n")
cat("============================================================\n")
print(descriptivos)

write_csv(descriptivos, file.path(RUTA_SALIDAS, "tabla_descriptivos.csv"))

capture.output(print(knitr::kable(descriptivos, format = "simple")), file = file.path(RUTA_SALIDAS, "tabla_descriptivos.txt"))
#..............................................................................



#..............................................................................
# MATRIZ DE CORRELACIONES DE PEARSON

matriz_pearson <- base %>%
  select(all_of(variables_finales)) %>%
  cor(use = "complete.obs", method = "pearson")

colnames(matriz_pearson) <- etiquetas_finales[variables_finales]
rownames(matriz_pearson) <- etiquetas_finales[variables_finales]

cat("\n============================================================\n")
cat("CORRELACIONES DE PEARSON\n")
cat("============================================================\n")
print(round(matriz_pearson, 3))

write.csv(round(matriz_pearson, 3), file.path(RUTA_SALIDAS, "tabla_correlaciones_pearson.csv"))
#..............................................................................



#..............................................................................
# MATRIZ DE CORRELACIONES DE SPEARMAN

matriz_spearman <- base %>%
  select(all_of(variables_finales)) %>%
  cor(use = "complete.obs", method = "spearman")

colnames(matriz_spearman) <- etiquetas_finales[variables_finales]
rownames(matriz_spearman) <- etiquetas_finales[variables_finales]

cat("\n============================================================\n")
cat("CORRELACIONES DE SPEARMAN\n")
cat("============================================================\n")
print(round(matriz_spearman, 3))

write.csv(round(matriz_spearman, 3), file.path(RUTA_SALIDAS, "tabla_correlaciones_spearman.csv"))
#..............................................................................


#..............................................................................
# PAQUETE UTILIZADO PARA VISUALIZAR LA MATRIZ DE CORRELACIONES
if (!requireNamespace("corrplot", quietly = TRUE)) install.packages("corrplot")

# GRÁFICO DE CORRELACIONES DE PEARSON

colores_corr <- colorRampPalette(c("#B22222", "#F7F7F7", "#1E3A8A"))(200)

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
  tl.font = 2,
  diag = FALSE,
  cl.cex = 0.9,
  mar = c(0, 0, 3, 0),
  title = "Matriz de correlaciones de Pearson"
)

dev.off()
#..............................................................................


#..............................................................................
# BASE EN FORMATO LARGO PARA LOS GRÁFICOS

base_larga <- base %>%
  select(fecha, all_of(variables_finales)) %>%
  pivot_longer(cols = all_of(variables_finales), names_to = "variable", values_to = "valor") %>%
  mutate(variable = dplyr::recode(variable, !!!etiquetas_finales))
#..............................................................................


#..............................................................................
# GRÁFICOS DE EVOLUCIÓN TEMPORAL
# 

grafico_series <- ggplot(base_larga, aes(x = fecha, y = valor, color = variable)) +
  geom_line(linewidth = 0.55) +
  scale_color_manual(values = paleta_variables) +
  facet_wrap(~variable, scales = "free_y", ncol = 2) +
  labs(
    title = "Evolución diaria de las variables del estudio",
    subtitle = paste("Periodo:", format(min(base$fecha)), "a", format(max(base$fecha))),
    x = "Fecha",
    y = "Valor"
  ) +
  theme_minimal(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0.5, color = "#081C15"),
    plot.subtitle = element_text(size = 11, hjust = 0.5, color = "#2D6A4F"),
    axis.title = element_text(face = "bold", color = "#1B4332"),
    axis.text = element_text(color = "#344E41"),
    strip.text = element_text(face = "bold", size = 11, color = "#081C15"),
    strip.background = element_rect(fill = "#B7E4C7", color = "#74C69D", linewidth = 0.7),
    panel.grid.major = element_line(color = "#D8F3DC", linewidth = 0.45),
    panel.grid.minor = element_blank(),
    panel.border = element_rect(color = "#95D5B2", fill = NA, linewidth = 0.8),
    plot.background = element_rect(fill = "white", color = NA),
    legend.position = "none"
  )

ggsave(file.path(RUTA_SALIDAS, "series_tiempo.png"), grafico_series, width = 10, height = 7, dpi = 300)
#..............................................................................



#..............................................................................
# HISTOGRAMAS Y CURVAS DE DENSIDAD


grafico_histogramas <- ggplot(base_larga, aes(x = valor, fill = variable)) +
  geom_histogram(aes(y = after_stat(density)), bins = 40, color = "white", alpha = 0.8) +
  geom_density(color = "#1B1B1B", linewidth = 0.7) +
  scale_fill_manual(values = paleta_variables) +
  facet_wrap(~variable, scales = "free", ncol = 2) +
  labs(
    title = "Distribución de las variables del estudio",
    x = "Valor",
    y = "Densidad"
  ) +
  theme_minimal(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0.5, color = "#081C15"),
    axis.title = element_text(face = "bold", color = "#1B4332"),
    axis.text = element_text(color = "#344E41"),
    strip.text = element_text(face = "bold", color = "#081C15"),
    strip.background = element_rect(fill = "#D8F3DC", color = "#95D5B2"),
    panel.grid.minor = element_blank(),
    legend.position = "none"
  )

ggsave(file.path(RUTA_SALIDAS, "histogramas.png"), grafico_histogramas, width = 10, height = 7, dpi = 300)
#..............................................................................



#..............................................................................
# BOXPLOTS DE LAS CINCO VARIABLES FINALES

grafico_boxplots_finales <- ggplot(base_larga, aes(x = variable, y = valor, fill = variable)) +
  geom_boxplot(alpha = 0.8, outlier.color = "#8B0000", outlier.fill = "#CD5C5C") +
  facet_wrap(~variable, scales = "free_y", ncol = 3) +
  scale_fill_manual(values = paleta_variables) +
  labs(
    title = "Diagramas de caja de las variables utilizadas en el análisis",
    subtitle = "Variables peruanas winsorizadas; variables estadounidenses sin transformación",
    x = NULL,
    y = "Valor"
  ) +
  theme_minimal(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0.5, color = "#2C3E50"),
    plot.subtitle = element_text(size = 11, hjust = 0.5, color = "#4F5D75"),
    axis.title = element_text(face = "bold", color = "#2C3E50"),
    axis.text = element_text(color = "#3A3A3A"),
    axis.text.x = element_blank(),
    strip.text = element_text(face = "bold", size = 11, color = "#2C3E50"),
    strip.background = element_rect(fill = "#F4F4F4", color = "#D9D9D9", linewidth = 0.6),
    panel.grid.major = element_line(color = "#EAEAEA", linewidth = 0.4),
    panel.grid.minor = element_blank(),
    panel.border = element_rect(color = "#D0D0D0", fill = NA, linewidth = 0.7),
    legend.position = "none",
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave(file.path(RUTA_SALIDAS, "boxplots_finales.png"), grafico_boxplots_finales,
       width = 10, height = 7, dpi = 300)
#..............................................................................



#..............................................................................
# DIAGRAMAS DE DISPERSIÓN

#---------------------------------------------------------------------------
#                     BONO PERUANO VS. EMBIG PERÚ
#----------------------------------------------------------------------------

grafico_disp_embig <- ggplot(base, aes(x = embig_peru_pp_w, y = bono_pe_10a_soles_w)) +
  geom_point(color = "#2E86AB", alpha = 0.50, size = 1.6) +
  geom_smooth(method = "lm", formula = y ~ x, color = "#1B4965", fill = "#A9D6E5", se = TRUE, linewidth = 0.9) +
  labs(
    title = "Bono soberano peruano a 10 años y EMBIG Perú",
    subtitle = "Relación entre el riesgo país y el rendimiento del bono soberano peruano",
    x = "EMBIG Perú (puntos porcentuales)",
    y = "Rendimiento del bono soberano peruano a 10 años (%)"
  ) +
  theme_light(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, color = "#1B4965"),
    plot.subtitle = element_text(size = 10.5, hjust = 0.5, color = "#457B9D"),
    axis.title = element_text(face = "bold", color = "#1B4965"),
    axis.text = element_text(color = "#344E41"),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave(file.path(RUTA_SALIDAS, "dispersion_bono_vs_embig.png"), grafico_disp_embig, width = 8, height = 6, dpi = 300)



#---------------------------------------------------------------------------
#             BONO PERUANO VS. TASA DE FONDOS FEDERALES
#---------------------------------------------------------------------------

grafico_disp_fed <- ggplot(base, aes(x = tasa_fondos_federales, y = bono_pe_10a_soles_w)) +
  geom_point(color = "#E76F51", alpha = 0.50, size = 1.6) +
  geom_smooth(method = "lm", formula = y ~ x, color = "#9A3412", fill = "#FBC4AB", se = TRUE, linewidth = 0.9) +
  labs(
    title = "Bono soberano peruano a 10 años y tasa de fondos federales",
    subtitle = "Relación entre la política monetaria de la Reserva Federal y el bono peruano",
    x = "Tasa efectiva de fondos federales (%)",
    y = "Rendimiento del bono soberano peruano a 10 años (%)"
  ) +
  theme_light(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, color = "#9A3412"),
    plot.subtitle = element_text(size = 10.5, hjust = 0.5, color = "#C2542D"),
    axis.title = element_text(face = "bold", color = "#9A3412"),
    axis.text = element_text(color = "#344E41"),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave(file.path(RUTA_SALIDAS, "dispersion_bono_vs_fed_funds.png"), grafico_disp_fed, width = 8, height = 6, dpi = 300)


#---------------------------------------------------------------------------
#             BONO PERUANO VS. TESORO DE EE. UU. A 2 AÑOS
#---------------------------------------------------------------------------

grafico_disp_tesoro2 <- ggplot(base, aes(x = tesoro_2a, y = bono_pe_10a_soles_w)) +
  geom_point(color = "#6A4C93", alpha = 0.50, size = 1.6) +
  geom_smooth(method = "lm", formula = y ~ x, color = "#3D2C5C", fill = "#C7B8E8", se = TRUE, linewidth = 0.9) +
  labs(
    title = "Bono soberano peruano a 10 años y Tesoro de EE. UU. a 2 años",
    subtitle = "Relación entre los rendimientos soberanos de Perú y Estados Unidos",
    x = "Rendimiento del Tesoro de EE. UU. a 2 años (%)",
    y = "Rendimiento del bono soberano peruano a 10 años (%)"
  ) +
  theme_light(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, color = "#3D2C5C"),
    plot.subtitle = element_text(size = 10.5, hjust = 0.5, color = "#6A4C93"),
    axis.title = element_text(face = "bold", color = "#3D2C5C"),
    axis.text = element_text(color = "#344E41"),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave(file.path(RUTA_SALIDAS, "dispersion_bono_vs_tesoro_2a.png"), grafico_disp_tesoro2, width = 8, height = 6, dpi = 300)


#---------------------------------------------------------------------------
#                BONO PERUANO VS. TESORO DE EE. UU. A 10 AÑOS
#---------------------------------------------------------------------------

grafico_disp_tesoro10 <- ggplot(base, aes(x = tesoro_10a, y = bono_pe_10a_soles_w)) +
  geom_point(color = "#F4A261", alpha = 0.55, size = 1.6) +
  geom_smooth(method = "lm", formula = y ~ x, color = "#B5651D", fill = "#FDE4C8", se = TRUE, linewidth = 0.9) +
  labs(
    title = "Bono soberano peruano a 10 años y Tesoro de EE. UU. a 10 años",
    subtitle = "Relación entre los rendimientos soberanos de largo plazo",
    x = "Rendimiento del Tesoro de EE. UU. a 10 años (%)",
    y = "Rendimiento del bono soberano peruano a 10 años (%)"
  ) +
  theme_light(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, color = "#B5651D"),
    plot.subtitle = element_text(size = 10.5, hjust = 0.5, color = "#D08432"),
    axis.title = element_text(face = "bold", color = "#B5651D"),
    axis.text = element_text(color = "#344E41"),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave(file.path(RUTA_SALIDAS, "dispersion_bono_vs_tesoro_10a.png"), grafico_disp_tesoro10, width = 8, height = 6, dpi = 300)



#..............................................................................
# BASE DERIVADA UTILIZADA EN EL ANÁLISIS

base_analisis <- base %>%
  select(
    fecha,
    bono_pe_10a_soles,
    bono_pe_10a_soles_w,
    embig_peru_pbs,
    embig_peru_pp,
    embig_peru_pp_w,
    tasa_fondos_federales,
    tesoro_2a,
    tesoro_10a
  )

write_csv(base_analisis, file.path(RUTA_SALIDAS, paste0("base_analisis_", CODIGO_MATRICULA, ".csv")))
#..............................................................................


# =====================================================================
#               ANÁLISIS ESTADÍSTICO INFERENCIAL Y ECONOMÉTRICO
# =====================================================================


#..............................................................................
# PAQUETE UTILIZADO PARA LAS PRUEBAS DE ESTACIONARIEDAD
# tseries proporciona las pruebas ADF y KPSS.
if (!requireNamespace("tseries", quietly = TRUE)) install.packages("tseries")

# PRUEBAS DE ESTACIONARIEDAD: ADF Y KPSS
#
# Justificación: las series financieras diarias suelen ser no estacionarias
# (tienen raíz unitaria). Estimar una regresión con variables no
# estacionarias puede producir una "regresión espuria" (R2 y significancia
# altos sin relación económica real). Antes de interpretar el modelo, se
# revisa si el bono peruano, el EMBIG, la Fed funds rate y los Tesoros son
# estacionarios en nivel.
#
# - ADF (Dickey-Fuller aumentado): H0 = la serie tiene raíz unitaria (no
#   estacionaria). p < 0.05 sugiere estacionariedad.
# - KPSS: H0 = la serie es estacionaria. p < 0.05 sugiere NO estacionariedad.
# Se usan ambas porque son complementarias (una prueba a favor de la raíz
# unitaria y la otra a favor de la estacionariedad).

probar_estacionariedad <- function(x, nombre_variable) {

  x <- na.omit(x)

  adf <- tseries::adf.test(x)
  kpss <- tseries::kpss.test(x, null = "Level")

  tibble(
    variable = nombre_variable,
    adf_estadistico = unname(adf$statistic),
    adf_p_valor = adf$p.value,
    kpss_estadistico = unname(kpss$statistic),
    kpss_p_valor = kpss$p.value,
    conclusion_preliminar = ifelse(
      adf$p.value < 0.05 & kpss$p.value >= 0.05,
      "Estacionaria en nivel",
      "Posible raíz unitaria (revisar en primeras diferencias)"
    )
  )
}

tabla_estacionariedad <- purrr::map2_dfr(
  list(
    base$bono_pe_10a_soles_w, base$embig_peru_pp_w, base$tasa_fondos_federales,
    base$tesoro_2a, base$tesoro_10a
  ),
  variables_finales,
  probar_estacionariedad
) %>%
  mutate(across(where(is.numeric), ~round(.x, 4)))

print(tabla_estacionariedad, width = Inf)

write_csv(tabla_estacionariedad, file.path(RUTA_SALIDAS, "tabla_estacionariedad_adf_kpss.csv"))
#..............................................................................


#..............................................................................
# PAQUETE UTILIZADO PARA LA CORRELACIÓN PARCIAL
# ppcor permite medir la relación entre dos variables controlando las demás.
if (!requireNamespace("ppcor", quietly = TRUE)) install.packages("ppcor")

# CORRELACIÓN PARCIAL

# Para cada correlación parcial se controla por las otras tres variables.

variable_endogena <- "bono_pe_10a_soles_w"

variables_exogenas <- c(
  "embig_peru_pp_w",
  "tasa_fondos_federales",
  "tesoro_2a",
  "tesoro_10a"
)

etiquetas_exogenas <- c(
  embig_peru_pp_w = "EMBIG Perú",
  tasa_fondos_federales = "Tasa de fondos federales",
  tesoro_2a = "Tesoro EE. UU. 2 años",
  tesoro_10a = "Tesoro EE. UU. 10 años"
)

calcular_cor_parcial <- function(exogena) {

  controles <- setdiff(variables_exogenas, exogena)

  datos <- base %>%
    select(all_of(c(variable_endogena, exogena, controles))) %>%
    drop_na()

  prueba <- ppcor::pcor.test(
    x = datos[[variable_endogena]],
    y = datos[[exogena]],
    z = datos[, controles],
    method = "pearson"
  )

  tibble(
    variable_exogena = etiquetas_exogenas[exogena],
    correlacion_parcial = unname(prueba$estimate),
    estadistico_t = unname(prueba$statistic),
    p_valor = prueba$p.value,
    n = nrow(datos),
    variables_control = paste(etiquetas_exogenas[controles], collapse = ", ")
  )
}

tabla_correlaciones_parciales <- purrr::map_dfr(
  variables_exogenas,
  calcular_cor_parcial
)

tabla_correlaciones_parciales <- tabla_correlaciones_parciales %>%
  mutate(
    p_valor_ajustado_holm = p.adjust(p_valor, method = "holm"),
    significativo_5pct = ifelse(p_valor_ajustado_holm < 0.05, "Sí", "No"),
    correlacion_parcial = round(correlacion_parcial, 4),
    estadistico_t = round(estadistico_t, 4),
    p_valor = round(p_valor, 5),
    p_valor_ajustado_holm = round(p_valor_ajustado_holm, 5)
  )

print(tabla_correlaciones_parciales, width = Inf)

write_csv(tabla_correlaciones_parciales, file.path(RUTA_SALIDAS, "tabla_correlaciones_parciales.csv"))
#...............................................................................


#...............................................................................
# DEFINICIÓN DEL MODELO DEL ESTUDIO
# ------------------------------------------------------------------------
# Variable endógena: bono_pe_10a_soles_w (rendimiento del bono soberano
#                     peruano a 10 años, winsorizado)
# Variables exógenas: embig_peru_pp_w, tasa_fondos_federales, tesoro_2a,
#                     tesoro_10a

modelo <- lm(
  bono_pe_10a_soles_w ~ embig_peru_pp_w + tasa_fondos_federales + tesoro_2a + tesoro_10a,
  data = base
)

summary(modelo)
#...............................................................................


#...............................................................................
# PAQUETE UTILIZADO PARA EL DIAGNÓSTICO DE MULTICOLINEALIDAD
# car::vif() calcula el factor de inflación de la varianza de cada regresor.
if (!requireNamespace("car", quietly = TRUE)) install.packages("car")

# MULTICOLINEALIDAD (VIF)
# ------------------------------------------------------------------------
# Se revisa primero porque, de haber colinealidad severa, hay que corregir
# la ESPECIFICACIÓN del modelo antes de interpretar cualquier coeficiente
# o de correr los demás diagnósticos.

vif_modelo <- car::vif(modelo)
print(vif_modelo)

tabla_vif <- tibble(
  variable = names(vif_modelo),
  vif = as.numeric(vif_modelo)
) %>%
  mutate(vif = round(vif, 3))

print(tabla_vif)

#INTERPRETACIÓN:
# tasa_fondos_federales y tesoro_2a presentan VIF elevados porque se mueven
# de forma muy similar. Para conservar la información de ambas series sin
# retirar Tesoro 2A, se reparametriza el modelo con la tasa Fed y el spread.
# Esta transformación no crea información nueva ni elimina la relación
# económica original; cambia la forma de representar ambas variables:
#     spread_tesoro2_fed = tesoro_2a - tasa_fondos_federales

base <- base %>%
  mutate(spread_tesoro2_fed = tesoro_2a - tasa_fondos_federales)

modelo <- lm(
  bono_pe_10a_soles_w ~ embig_peru_pp_w + tasa_fondos_federales +
    spread_tesoro2_fed + tesoro_10a,
  data = base
)

# Se comprueba si, bajo esta parametrización, los VIF quedan por debajo de 5.
# Este criterio se utiliza como referencia práctica y no como regla absoluta.
vif_modelo <- car::vif(modelo)
print(vif_modelo)
#...............................................................................


#...............................................................................
# RESIDUOS DEL MODELO FINAL (insumo para los diagnósticos siguientes)

datos_residuos <- tibble(
  ajustados = fitted(modelo),
  residuos = residuals(modelo)
)

grafico_residuos <- ggplot(datos_residuos, aes(x = ajustados, y = residuos)) +
  geom_point(color = "#2A9D8F", alpha = 0.50, size = 1.5) +
  geom_hline(yintercept = 0, color = "#8B0000", linetype = "dashed", linewidth = 0.8) +
  geom_smooth(method = "loess", se = FALSE, color = "#264653", linewidth = 0.9) +
  labs(
    title = "Residuos frente a valores ajustados",
    subtitle = "Modelo final (con spread Tesoro 2A - Fed funds)",
    x = "Valores ajustados",
    y = "Residuos"
  ) +
  theme_light(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, color = "#264653"),
    plot.subtitle = element_text(size = 11, hjust = 0.5, color = "#2A9D8F"),
    axis.title = element_text(face = "bold", color = "#264653"),
    axis.text = element_text(color = "#344E41"),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave(file.path(RUTA_SALIDAS, "residuos_vs_ajustados.png"), grafico_residuos, width = 8, height = 6, dpi = 300)
#...............................................................................


#...............................................................................
# PAQUETE UTILIZADO PARA LOS DIAGNÓSTICOS DEL MODELO
# lmtest proporciona Breusch-Pagan, Breusch-Godfrey, Durbin-Watson y coeftest().
if (!requireNamespace("lmtest", quietly = TRUE)) install.packages("lmtest")

# HETEROCEDASTICIDAD: BREUSCH-PAGAN

prueba_bp <- lmtest::bptest(modelo)
print(prueba_bp)
#...............................................................................


#...............................................................................
# AUTOCORRELACIÓN: BREUSCH-GODFREY Y DURBIN-WATSON

prueba_bg <- lmtest::bgtest(modelo, order = 1)
print(prueba_bg)

prueba_dw <- lmtest::dwtest(modelo)
print(prueba_dw)

# ------------------------------------------------------------------------
# PAQUETE UTILIZADO PARA LA MATRIZ ROBUSTA HAC
# sandwich::NeweyWest() corrige los errores estándar frente a
# heterocedasticidad y autocorrelación serial.
if (!requireNamespace("sandwich", quietly = TRUE)) install.packages("sandwich")

# CORRECCIÓN CONJUNTA: HETEROCEDASTICIDAD + AUTOCORRELACIÓN (Newey-West/HAC)
# ------------------------------------------------------------------------
# Como el modelo mostró heterocedasticidad  Y autocorrelación
# (este paso), la corrección que resuelve ambas a la vez es Newey-West
# (HAC, Heteroskedasticity and Autocorrelation Consistent). Estos son los
# errores estándar y p-valores que se reportan como resultado final —
# NO los del lm() normal.

modelo_hac <- lmtest::coeftest(
  modelo,
  vcov. = sandwich::NeweyWest(
    modelo,
    lag = 5,
    prewhite = FALSE,
    adjust = TRUE
  )
)

print(modelo_hac)
#...............................................................................


#...............................................................................
# PAQUETE UTILIZADO PARA LA PRUEBA DE NORMALIDAD
if (!requireNamespace("tseries", quietly = TRUE)) install.packages("tseries")

# NORMALIDAD DE LOS RESIDUOS: JARQUE-BERA

prueba_jb <- tseries::jarque.bera.test(residuals(modelo))
print(prueba_jb)
#...............................................................................


#...............................................................................
# PASO 7. ACF Y PACF DE LOS RESIDUOS
# Complementa a Breusch-Godfrey/Durbin-Watson mostrando visualmente en qué
# rezagos persiste la autocorrelación de los residuos.

png(
  file.path(RUTA_SALIDAS, "acf_pacf_residuos.png"),
  width = 2000,
  height = 1000,
  res = 220
)

par(mfrow = c(1, 2), family = "Georgia")

acf(residuals(modelo), main = "ACF de los residuos", col = "#2A9D8F", lwd = 2)
pacf(residuals(modelo), main = "PACF de los residuos", col = "#E76F51", lwd = 2)

dev.off()
#...............................................................................


#...............................................................................
# RESULTADO FINAL: COEFICIENTES, R2, R2 AJUSTADO Y P-VALUE GLOBAL
# ------------------------------------------------------------------------

resumen_modelo <- summary(modelo)

cat("\n============================================================\n")
cat("MODELO FINAL: COEFICIENTES (estimate) Y SIGNIFICANCIA HAC\n")
cat("============================================================\n")
print(modelo_hac)

cat("\nR2:", round(resumen_modelo$r.squared, 4), "\n")
cat("R2 ajustado:", round(resumen_modelo$adj.r.squared, 4), "\n")

f <- resumen_modelo$fstatistic
p_global <- pf(f[1], f[2], f[3], lower.tail = FALSE)
cat("P-value global del modelo:", format.pval(p_global, digits = 4), "\n")
#...............................................................................


#...............................................................................
# GRÁFICO DE HETEROCEDASTICIDAD DEL MODELO FINAL (para el informe)
# La corrección Newey-West (HAC) se aplica a la inferencia estadística;
# no modifica los residuos ni los valores ajustados del modelo, por eso
# el gráfico se ve igual al de "Residuos frente a valores ajustados" del
# Paso 3 — aquí se deja con el subtítulo orientado al informe final.

grafico_heterocedasticidad <- ggplot(datos_residuos, aes(x = ajustados, y = residuos)) +
  geom_point(color = "#2A9D8F", alpha = 0.45, size = 1.4) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, color = "#D00000", linewidth = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "#264653", linewidth = 0.7) +
  labs(
    title = "Residuos frente a valores ajustados",
    subtitle = "Modelo final, con inferencia robusta Newey-West (HAC)",
    x = "Valores ajustados",
    y = "Residuos"
  ) +
  theme_minimal(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0.5, color = "#264653"),
    plot.subtitle = element_text(size = 11, hjust = 0.5, color = "#2A9D8F"),
    axis.title = element_text(face = "bold", color = "#264653"),
    axis.text = element_text(color = "#344E41"),
    panel.grid.major = element_line(color = "#D8F3DC", linewidth = 0.4),
    panel.grid.minor = element_blank(),
    panel.border = element_rect(color = "#95D5B2", fill = NA, linewidth = 0.8)
  )

# Muestra el gráfico solamente cuando el script se ejecuta de forma interactiva en RStudio.
if (interactive()) print(grafico_heterocedasticidad)

ggsave(file.path(RUTA_SALIDAS, "heterocedasticidad_modelo_final.png"), grafico_heterocedasticidad, width = 9, height = 6, dpi = 300)
#...............................................................................


#...............................................................................
# COEFICIENTE DE LA FED A TRAVÉS DEL TIEMPO
# (REGRESIÓN MÓVIL / ROLLING REGRESSION)
# ------------------------------------------------------------------------
# En vez de un solo coeficiente fijo para todo 2010-2025, se
# reestima el mismo modelo en ventanas móviles de ~1 año para ver si la
# sensibilidad del bono peruano a la tasa de la Fed cambia según el ciclo
# de política monetaria (ej. ciclo de subidas 2015-2018, tasas en cero en
# 2020-2021, ciclo agresivo de subidas 2022-2023). Esto responde de forma
# directa y visual la pregunta "¿EN QUÉ MEDIDA se relacionan?": muestra que
# la relación no es un número fijo, sino que varía en intensidad con el
# tiempo.

ventana <- 252   # ~ 1 año de observaciones diarias
paso <- 5        # se reestima cada 5 observaciones (más rápido; la curva sale igual de suave)

base_ordenada <- base %>%
  arrange(fecha) %>%
  drop_na(bono_pe_10a_soles_w, embig_peru_pp_w, tasa_fondos_federales,
          spread_tesoro2_fed, tesoro_10a)

n_obs <- nrow(base_ordenada)
indices_inicio <- seq(1, n_obs - ventana + 1, by = paso)

calcular_coef_movil <- function(i) {

  datos_ventana <- base_ordenada[i:(i + ventana - 1), ]

  modelo_ventana <- lm(
    bono_pe_10a_soles_w ~ embig_peru_pp_w + tasa_fondos_federales +
      spread_tesoro2_fed + tesoro_10a,
    data = datos_ventana
  )

  ic <- confint(modelo_ventana)["tasa_fondos_federales", ]

  tibble(
    fecha = datos_ventana$fecha[ventana],
    coef_fed = coef(modelo_ventana)["tasa_fondos_federales"],
    ic_inferior = ic[1],
    ic_superior = ic[2]
  )
}

rolling_coef_fed <- purrr::map_dfr(indices_inicio, calcular_coef_movil)

write_csv(rolling_coef_fed, file.path(RUTA_SALIDAS, "tabla_coeficiente_movil_fed.csv"))

# Ciclos de subida de tasas de la Fed (referencia histórica conocida), para
# contextualizar visualmente los cambios en el coeficiente. Ajusta las
# fechas si tu profesor te pide una fuente exacta (FOMC/FRED).
ciclos_subida_fed <- tibble(
  inicio = as.Date(c("2015-12-01", "2022-03-01")),
  fin = as.Date(c("2018-12-01", "2023-07-01")),
  etiqueta = c("Ciclo de subidas 2015-2018", "Ciclo de subidas 2022-2023")
)

grafico_coef_movil_fed <- ggplot() +
  geom_rect(
    data = ciclos_subida_fed,
    aes(xmin = inicio, xmax = fin, ymin = -Inf, ymax = Inf),
    fill = "#FDE4C8", alpha = 0.5
  ) +
  geom_ribbon(
    data = rolling_coef_fed,
    aes(x = fecha, ymin = ic_inferior, ymax = ic_superior),
    fill = "#8ECDDD", alpha = 0.45
  ) +
  geom_line(
    data = rolling_coef_fed,
    aes(x = fecha, y = coef_fed),
    color = "#023E8A", linewidth = 0.8
  ) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "#8B0000", linewidth = 0.7) +
  labs(
    title = "Sensibilidad del bono peruano a la tasa de la Fed a través del tiempo",
    subtitle = paste0(
      "Coeficiente móvil (ventana de ", ventana,
      " obs. \u2248 1 año) con intervalo de confianza al 95%; sombreado: ciclos de subida de tasas"
    ),
    x = "Fecha",
    y = "Coeficiente de tasa_fondos_federales"
  ) +
  theme_minimal(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, color = "#03045E"),
    plot.subtitle = element_text(size = 10.5, hjust = 0.5, color = "#0077B6"),
    axis.title = element_text(face = "bold", color = "#03045E"),
    axis.text = element_text(color = "#344E41"),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  )

# Muestra el gráfico únicamente cuando se trabaja de forma interactiva en RStudio.
if (interactive()) print(grafico_coef_movil_fed)

ggsave(file.path(RUTA_SALIDAS, "coeficiente_movil_fed.png"), grafico_coef_movil_fed, width = 10, height = 6, dpi = 300)
#...............................................................................

#...............................................................................
# PAQUETE UTILIZADO PARA LA IMPORTANCIA RELATIVA
# relaimpo permite descomponer el R2 del modelo mediante el método LMG.
if (!requireNamespace("relaimpo", quietly = TRUE)) install.packages("relaimpo")

# IMPORTANCIA RELATIVA DE CADA VARIABLE
# (DESCOMPOSICIÓN DEL R² — MÉTODO LMG)
# ------------------------------------------------------------------------
# El coeficiente de una variable dice CÓMO se relaciona con el bono, pero
# no dice qué tanto "peso" tiene esa variable dentro de todo lo que el
# modelo logra explicar. El método LMG (Lindeman-Merenda-Gold) reparte el
# R² total del modelo entre las 4 variables de forma justa, incluso cuando
# están correlacionadas entre sí (a diferencia de simplemente comparar
# coeficientes o p-valores). Esto responde de forma muy concreta la
# pregunta de investigación: de la relación entre el bono peruano y sus
# determinantes, ¿cuánto le corresponde al riesgo país (EMBIG) frente a
# las condiciones de EE. UU. (Fed funds, spread, Tesoro 10A)?

importancia_relativa <- relaimpo::calc.relimp(modelo, type = "lmg", rela = TRUE)

etiquetas_modelo <- c(
  embig_peru_pp_w = "EMBIG Perú",
  tasa_fondos_federales = "Tasa de fondos federales",
  spread_tesoro2_fed = "Spread Tesoro 2A - Fed",
  tesoro_10a = "Tesoro EE. UU. 10 años"
)

tabla_importancia <- tibble(
  variable = names(importancia_relativa$lmg),
  importancia_pct = as.numeric(importancia_relativa$lmg) * 100
) %>%
  mutate(
    variable_label = etiquetas_modelo[variable],
    importancia_pct = round(importancia_pct, 2)
  ) %>%
  arrange(desc(importancia_pct))

print(tabla_importancia)
write_csv(tabla_importancia, file.path(RUTA_SALIDAS, "tabla_importancia_relativa.csv"))

paleta_importancia <- c(
  "EMBIG Perú" = "#66C2A5",
  "Tasa de fondos federales" = "#8DA0CB",
  "Spread Tesoro 2A - Fed" = "#FC8D62",
  "Tesoro EE. UU. 10 años" = "#E78AC3"
)

grafico_importancia <- ggplot(
  tabla_importancia,
  aes(x = reorder(variable_label, importancia_pct), y = importancia_pct, fill = variable_label)
) +
  geom_col(width = 0.65) +
  geom_text(
    aes(label = paste0(importancia_pct, "%")),
    hjust = -0.15, family = "Georgia", fontface = "bold", color = "#2C3E50"
  ) +
  coord_flip(clip = "off") +
  scale_fill_manual(values = paleta_importancia) +
  scale_y_continuous(limits = c(0, max(tabla_importancia$importancia_pct) * 1.2)) +
  labs(
    title = "¿Qué variable explica más el rendimiento del bono peruano?",
    subtitle = paste0(
      "Descomposición del R\u00b2 (", round(summary(modelo)$r.squared * 100, 1),
      "%) por variable \u2014 método LMG"
    ),
    x = NULL,
    y = "% del R\u00b2 explicado"
  ) +
  theme_minimal(base_size = 12, base_family = "Georgia") +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, color = "#2C3E50"),
    plot.subtitle = element_text(size = 10.5, hjust = 0.5, color = "#4F5D75"),
    axis.text = element_text(color = "#344E41", size = 11),
    axis.title = element_text(face = "bold", color = "#2C3E50"),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_blank(),
    legend.position = "none",
    plot.background = element_rect(fill = "white", color = NA)
  )

# Muestra el gráfico únicamente cuando se trabaja de forma interactiva en RStudio.
if (interactive()) print(grafico_importancia)

ggsave(file.path(RUTA_SALIDAS, "importancia_relativa_variables.png"), grafico_importancia, width = 9, height = 5.5, dpi = 300)
#...............................................................................


# =====================================================================
# 25. INFORMACIÓN DE LA SESIÓN DE R
# =====================================================================
#
# sessionInfo() registra:
#
# - versión de R;
# - sistema operativo;
# - paquetes cargados;
# - versiones de los paquetes.
#
# Esto ayuda a documentar la reproducibilidad del análisis.
# =====================================================================

capture.output(sessionInfo(), file = file.path(RUTA_SALIDAS, "sessionInfo_R.txt"))
