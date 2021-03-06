% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/calibrate.R
\name{calibrate}
\alias{calibrate}
\title{Calibrate cropping and rotation parameters}
\usage{
calibrate(dir = ".", rotate = 90, range = 2, thresh = 0.03,
  invert = TRUE, rough_pad = c(0, 0, 0, 0), fine_pad = c(10, 10, 10, 10),
  default_crop = NULL, overwrite = FALSE, display = TRUE,
  save_plate = !display)
}
\arguments{
\item{dir}{Directory of images to process.}

\item{rotate}{A rough angle in degrees clockwise to rotate each plate. The
rotation angle will be further calibrated after applying this rotation.
Defaults to \code{90}.}

\item{range}{Range to explore (in degrees) when calibrating rotation angle.
Defaults to \code{2}.}

\item{thresh}{Fraction of foreground pixels needed to identify plate
boundaries when rough cropping. Defaults to \code{0.03}.}

\item{invert}{Should the image be inverted? Defaults to \code{TRUE}.
Recommended \code{TRUE} if colonies are darker than the plate.}

\item{default_crop}{If not \code{NULL} then use this dataframe as the
default crop coordinates.}

\item{overwrite}{Should existing crop calibration be overwritten?
Defaults to \code{FALSE}.}

\item{display}{Should cropped images be displayed for review?
Defaults to \code{TRUE}.}

\item{save_plate}{Should the calibrated plate be saved rather than
displayed (useful when calibrating many plates)? Defaults to \code{!display}.}
}
\description{
This function calibrates plate cropping and rotation parameters for an image
with an arbritrarily sized grid of plates.
}
\details{
Crop calibration procedes through the following 3 steps:

\enumerate{
  \item Rough crop
  \item Rotate
  \item Fine crop
}

Rough cropping relies on high contrast between plates. If
\code{invert = TRUE} plates should be light and the region between plates
should be dark, and vice versa if \code{invert = FALSE}.

Fine cropping finds the nearest object edge (problematic for plates without
any growth on the intended grid edges).
}
