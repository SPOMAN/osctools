#' Pick peaks in datasets interactively
#'
#' @description
#' `peak_picker()` is an interactive tool (a shinyGadget) for finding peaks in datasets (e.g. a spectrum). After loading the dataset and specifying the columns, you can easily select peaks by clicking on the dataset. The gadget will automatically try to determine the nearest peak to the click and select it. Peaks can be deselected by clicking again.
#'
#' When you are finished press "Done". The gadget will place a piece of code in your clipboard that you should paste into your script for reproducibility.
#'
#' @param df A tibble containing the data to pick peaks in
#' @param x Column containing the x-values
#' @param y Column containing the y-values
#' @param find_nearest If TRUE (the default) the gadget will attempt to find the nearest peak when clicking on a point in the dataset. This is disabled by setting this option to FALSE, in which case the point nearest to the click will be selected.
#'
#' @return The original dataset with an additional column "peak", which indicates TRUE/FALSE if the given row is a peak.
#' @export
#'
#' @examples
#' library(tidyverse)
#' df <- tibble(x1 = seq(0.1, 25, 0.01), y1 = sin(x1)^2/x1)
#'
#' peak_picker(df, x1, y1)
#' df <- df %>% add_peaks(c(108,451,770,1086,1401,1716,2031,2345))
#'
#' # After adding peaks, the plot from the gadget can be reproduced using plot_peaks()
#' df %>% plot_peaks(x1, y1)


peak_picker <- function(df, x, y, find_nearest = TRUE) {
  requireNamespace("shiny", quietly = TRUE)
  requireNamespace("miniUI", quietly = TRUE)
  input_name <- deparse(substitute(df))

  x <- rlang::enquo(x)
  y <- rlang::enquo(y)

  data <- generic_df(df, !!x, !!y)


ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar("Select peaks by clicking on the figure below"),
    miniUI::miniContentPanel(
      shiny::plotOutput("plot1", height = "100%", click = "plot1_click")
    )
  )

  server <- function(input, output, session) {
    v <- shiny::reactiveValues(
      selectedData = data[0,]
    )

    shiny::observeEvent(input$plot1_click, {
      X1 <- shiny::nearPoints(data, input$plot1_click, maxpoints = 1, threshold = 25)

      if (nrow(X1) > 0 ) {

        if (find_nearest) {
          # Find nearest peak
          peak_ind <- find_peak(data$x, data$y, which(data$x == X1$x))
          if (!is.na(peak_ind)) {
            X1 <- data[peak_ind,]
          } else {
            X1 <- X1[0,]
          }
        }

        X_bind <- rbind(v$selectedData, X1)

        if (nrow(X_bind) == nrow(dplyr::distinct(X_bind))) {
          v$selectedData <- rbind(v$selectedData, X1) %>% dplyr::arrange(x)
        } else {
          v$selectedData <- dplyr::anti_join(v$selectedData, X1, by = c("x", "y"))
        }
      }
    })

    output$list<-shiny::renderPrint({
      v$selectedData
    })
    output$plot1 <- shiny::renderPlot({
      peak_indices <- match(v$selectedData$x, data$x)
      data %>% add_peaks(peak_indices) %>% plot_peaks(x, y)
    })

    shiny::observeEvent(input$done, {
      peak_indices <- match(v$selectedData$x, data$x)
      return_data <- df %>% add_peaks(peak_indices)

      cat(paste0(length(peak_indices)," peaks found in the dataset\n"))
      cat("The add_peaks() function below has been copied to the clipboard!\n")
      cat("Please paste it in your script for reproducibility.\n")
      peak_vec <- paste(peak_indices, collapse = ",")
      res_string = paste0(input_name, ' <- ', input_name,' %>% add_peaks(c(', peak_vec ,'))')
      cat(paste0("    ", res_string, "\n"))
      clipr::write_clip(res_string, return_new = FALSE)

      shiny::stopApp(returnValue = invisible(return_data))
    })
  }
  shiny::runGadget(ui, server)
}


#' Return a standard dataframe with two columns (x and y)
#'
#' @param df Dataframe to be converted
#' @param x Column containing x-coordinates
#' @param y Column containing y-coordinates
#'
#' @return A standard tibble with the given data in two columns (x and y)
#'
#' @examples
#' library(tidyverse)
#' df <- tibble(x1 = seq(0, 5, 0.1), y1 = sin(x))
#' generic_df(df, x1, y1)
#'
generic_df <- function(df, x, y) {
  x = rlang::enquo(x)
  y = rlang::enquo(y)

  tibble::tibble(x = dplyr::pull(df, !!x), y = dplyr::pull(df, !!y))
}


#' Add peak indicators at the given indices
#'
#' @param df Dataframe with dataset (e.g. x- and y-values of a spectrum)
#' @param indices Vector of integer indices indicating peak positions
#'
#' @return tbl_df with an additional column indicating whether the row is a peak
#' @export
#'
#' @examples
#' library(tidyverse)
#' tibble(x1 = seq(0.1, 9, 0.01), y1 = sin(x1)) %>%
#'   add_peaks(c(148,776))
add_peaks <- function(df, indices) {
  return_data <- df %>% dplyr::mutate(peak = FALSE)
  return_data$peak[indices] <- TRUE
  return_data
}

#' Returns the index of the nearest peak
#'
#' Calculates the gradient at the given index and then travels along the line in the upwards direction until a peak is found
#'
#' @param x Vector of x-values
#' @param y Vector of y-values
#' @param ind Index to start peak search
#'
#' @return integer index of peak
#'
find_peak <- function(x, y, ind) {
  grad <- find_gradient(x, y, ind)
  if (is.na(grad)) return(NA)
  if (grad > 0) move <- 1 else move <- -1

  if (y[ind + move] > y[ind]) {
    find_peak(x, y, ind + move)
  } else {
    return(ind)
  }
}


#' Local gradient at given index
#'
#' @param x Vector of x-values
#' @param y Vector of y-values
#' @param ind Index to calculate the gradient at
#'
#' @return numeric
#'
find_gradient <- function(x, y, ind) {
  if (ind == 1 | ind == length(x)) {
    warning("Index out of bounds")
    return(NA)
  }

  (y[ind + 1] - y[ind - 1]) / (x[ind + 1] - x[ind - 1])
}

#' Plot a dataset contain defined peaks
#'
#' @param df Any dataframe with e.g. a spectrum or similar. It must contain a column 'peak' containing TRUE/FALSE values indicating the presence of peaks.
#' @param x The values plotted on the x-axis (e.g. wavelength)
#' @param y The values plotted on the y-axis (e.g. intensity/counts)
#'
#' @return A ggplot
#' @export
#'
#' @examples
#' library(tidyverse)
#' tibble(x1 = seq(0.1, 9, 0.01), y1 = sin(x1)) %>%
#'   add_peaks(c(148,776)) %>%
#'   plot_peaks(x1, y1)
plot_peaks <- function(df, x, y) {
  if (!("peak" %in% colnames(df))) stop("Column peaks not found")

  x <- rlang::enquo(x)
  y <- rlang::enquo(y)

  data <- generic_df(df, !!x, !!y) %>% dplyr::mutate(peak = df$peak)

  nudge_dist <- (max(data$x) - min(data$x)) / 100
  data %>%
    ggplot2::ggplot(ggplot2::aes(x, y)) +
    ggplot2::geom_line() +
    ggplot2::geom_text(data = . %>% dplyr::filter(peak), ggplot2::aes(x, y, label = round(x, digits = 1)), size = 3, nudge_y = nudge_dist * 9, color = "red") +
    ggplot2::geom_segment(data = . %>% dplyr::filter(peak), ggplot2::aes(x = x, xend = x, y = y + nudge_dist*2, yend = y + nudge_dist*5), color = "red")
}
