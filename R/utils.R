# Utils: miscelaneous ---------------------------------------------------------

# Assign column names in pipline
# @param x Data frame or matrix
# @param names Character; Column names to assign to x

assign_names <- function(x, names) { colnames(x) <- names; return(x) }

# Check status of screenmill
screenmill_status <- function(dir,
                              file_anno = 'screenmill-annotations.csv',
                              file_crop = 'screenmill-calibration-crop.csv',
                              file_grid = 'screenmill-calibration-grid.csv',
                              file_keys = 'screenmill-collection-keys.csv',
                              file_coll = 'screenmill-collections.csv',
                              file_msmt = 'screenmill-measurements.csv',
                              file_mdia = 'screenmill-media.csv',
                              file_qury = 'screenmill-queries.csv',
                              file_trea = 'screenmill-treatments.csv',
                              file_revw = 'screenmill-review-times.csv') {
  assert_that(is.dir(dir))
  dir <- gsub('/$', '', dir)

  paths <-
    file.path(dir, c(
      # Annotate
      file_anno, file_keys, file_coll, file_mdia, file_qury, file_trea,
      # Calibrate           Measure    Review
      file_crop, file_grid, file_msmt, file_revw
    ))

  list(
    flag = list(
      annotated  = all(file.exists(paths[1:6])),
      calibrated = all(file.exists(paths[7:8])),
      measured   = file.exists(paths[9]),
      reviewed   = file.exists(paths[10])
    ),
    path = list(
      annotations      = paths[1],
      collection_keys  = paths[2],
      collections      = paths[3],
      media            = paths[4],
      queries          = paths[5],
      treatments       = paths[6],
      calibration_crop = paths[7],
      calibration_grid = paths[8],
      measurements     = paths[9],
      review_times     = paths[10]
    ),
    dir = dir
  )
}

# Utils: read_cm --------------------------------------------------------------

# Parse names in colony measurement log file
# @param lines Character; Parse plate lines from CM engine log.
# @param by Delimiter used to split plate names, numbers, and conditions.
#' @importFrom stringr str_count str_replace

parse_names <- function(lines, by = ',') {

  # Add commas if missing
  commas <- sapply(2 - str_count(lines, ','), function(x) paste(rep(',', x), collapse = ''))
  lines <- str_replace(lines, '(?=(\\.[^\\.]*$))', commas)

  # Split lines and combine
  do.call(rbind, strsplit(lines, by)) %>%
    assign_names(c('scan_name', 'plate', 'scan_cond')) %>%
    as.data.frame(stringsAsFactors = FALSE) %>%
    mutate_(
      id        = ~paste(scan_name, plate, scan_cond, sep = ','),
      plate     = ~as.integer(plate),
      scan_cond = ~gsub('\\.[^\\.]*$', '', scan_cond),
      scan_cond = ~ifelse(is.na(scan_cond) | scan_cond == '', 'none', scan_cond)
    )
}

# Parse measurements in colony measurement log file
# @param lines Character; Vector of measurement lines from CM engine log.
# @param by Delimiter used to split measurements. Defaults to \code{\\\\t}.

parse_measurements <- function(lines, by) {
  tbl <- do.call(rbind, strsplit(lines, by))

  if (ncol(tbl) == 2) {
    tbl %>%
      assign_names(c('size', 'circ')) %>%
      as.data.frame(stringsAsFactors = FALSE) %>%
      mutate_(size = ~as.numeric(size), circ = ~as.numeric(circ))
  } else if (ncol(tbl) == 1) {
    tbl %>%
      assign_names('size') %>%
      as.data.frame(stringsAsFactors = FALSE) %>%
      mutate_(size = ~as.numeric(size), circ = NA)
  } else {
    stop('Too many measurement columns')
  }
}

# Map strain replicate to measurements
# @param librows Integer; number of rows in strain library.
# @param libcols Integer; number of columns in strain library.
# @param replicates Integer; number of strain replicates in screen.
# @param nobs Integer; number of observations in screen.

map_replicate <- function(librows, libcols, replicates, nobs) {
  # map plate positions to replicate numbers
  (matrix(1, nrow = librows, ncol = libcols) %x%
     matrix(1:replicates, nrow = sqrt(replicates), byrow = TRUE)) %>%
    rep(length.out = nobs) %>%
    as.integer
}

# Map strain library column to measurements
# @param libcols Integer; number of columns in strain library.
# @param replicates Integer; number of strain replicates in screen.
# @param nrows Integer; number of rows on plate.
# @param ncols Integer; number of columns on plate.
# @param nobs Integer; number of observations in screen.

map_column <- function(libcols, replicates, nrows, ncols, nobs) {
  # map plate positions to strain library columns
  matrix(
    rep(1:libcols, each = nrows * sqrt(replicates)),
    nrow = nrows, ncol = ncols
  ) %>%
  rep(length.out = nobs)
}

# Map strain library row to measurements
# @param librows Integer; number of rows in strain library.
# @param replicates Integer; number of strain replicates in screen.
# @param nobs Integer; number of observations in screen.

map_row <- function(librows, replicates, nobs) {
  # map plate positions to strain library rows
  rep(LETTERS[1:librows], each = sqrt(replicates), length.out = nobs)
}

# Utils: read_dr --------------------------------------------------------------

# Find table header in text file
# @param path Character; path to file.
# @param match Regular expression used to match header line.
# @param delim Delimiter used to split header
# @param max Maximum number of lines to check

find_header <- function(path, match, delim, max = 100) {
  # Open file
  con <- file(path, open = "r")
  on.exit(close(con))
  # Find line corresponding to header
  line <- 1
  while (length(header <- readLines(con, n = 1, warn = FALSE)) > 0) {
    if (grepl(match, header[[1]])) break
    else line <- line + 1
    if (line > max) stop('Header not found within first ', max, 'lines.')
  }
  return(list(line = line, header = unlist(strsplit(header, delim))))
}


# Utils: read_plate_layout ------------------------------------------------------------------------

# Gather annotated plate in wide format into long format.
#
# Given a table with columns "row", "1", "2", ... gather everything but the "row"
# column into a table with variables "row", "column", `value`, "plate".
#
# @param path Path to CSV to gather
# @param value Name of value variable
# @param plate_pattern Regex used to extract plate number from `path`
#
# @details It is easiest to annotate e.g. a 96 well plate with strain, plasmid,
# OD600 etc. information in a way that looks visually similar to the plate.
# However this results in multiple tables (one for each annotated variable) in
# wide format. This function will convert such tables into long format such
# that each variable is in a single column rather than spread out in the grid
# style plate layout. Multiple gathered annotations can easily be joined to
# a single table
#
#' @importFrom readr read_csv cols
#' @importFrom tidyr gather_
#' @importFrom stringr str_extract regex

plate_gather <- function(path, value, plate_pattern = '(?<=(plate))[0-9]{1,}') {

  plate_numb <- as.integer(str_extract(basename(path), regex(plate_pattern, ignore_case = T)))
  if (is.na(plate_numb)) stop('Failed to determine plate number for:\n', basename(path))

  readr::read_csv(path, col_types = readr::cols()) %>%
    tidyr::gather_(
      'column',
      value,
      dplyr::select_vars(names(.), -dplyr::matches('row')), # gathers all columns but 'row'
      convert = T                                           # Type convert after gathering
    ) %>%
    dplyr::mutate(plate = plate_numb)
}

# Utils: new_strain_collection ------------------------------------------------

# Expand vector of letters
# @param len Integer; desired length letter combinations
# @param letters Character; vector of letters.
expand_letters <- function(len, letters) {
  out <- character(len)
  out[1:length(letters)] <- letters
  i <- 1
  while (any(out == '')) {
    from <- (length(letters) * i) + 1
    to   <- from + length(letters) - 1
    out[from:to] <- paste0(out[i], letters)
    i <- i + 1
  }
  return(out)
}



# Utils: Calibration ----------------------------------------------------------

# Rough crop a grid of plates
#
# Finds the rough plate edges for a grid of plates.
#
# @param img Either an "Image" object (see \link[EBImage]{readImage}), or a
#   matrix.
# @param thresh Fraction of foreground pixels needed to identify plate
#   boundaries. Defaults to \code{0.03}.
# @param invert Should the image be inverted? Defaults to \code{TRUE}.
#   Recommended \code{FALSE} if region between plates is lighter than the
#   plates. This is faster than manual inversion of entire image.
# @param pad Number of pixels to add (or remove) from detected plate edges.
#   Defaults to \code{c(0, 0, 0, 0)} which adds 0 pixels to the
#   left, right, top, and bottom coordinates of each plate respectively.
#   Negative values will remove pixels.
# @param display Should the resulting cropped images be displayed?
#   Defaults to \code{FALSE}.
#
# @details
#   Rough crops for a grid of plates are detected by thresholding by the
#   brightness of the image (can be adjusted using the \code{thresh} argument).
#   Rows and columns are then scanned to identify locations with a large number
#   of pixels that are more than the threshold pixel intensity. These transitions
#   are used to define the plate edges. For best results, the grid should be
#   approximately square to the edge of the image. Plate positions are numbered
#   from left to right, top to bottom.
#
# @return
#   \code{rough_crop} returns a dataframe with the following columns:
#
#   \item{position}{Integer position of plate in grid (row-wise).}
#   \item{top}{The rough top edge of the plate.}
#   \item{left}{The rough left edge of the plate.}
#   \item{right}{The rough right edge of the plate.}
#   \item{bot}{The rough bottom edge of the plate.}

rough_crop <- function(img, thresh, invert, pad) {

  small <- EBImage::resize(img, h = ncol(img) / 10) > 0.5

  rows <-
    rowSums(small) %>%
    find_valleys(thr = thresh * nrow(small), invert = invert) %>%
    mutate_at(vars(-n), funs(. * 10)) %>%
    rename_(plate_x = ~mid, plate_row = ~n, rough_l = ~left, rough_r = ~right)

  cols <-
    colSums(small) %>%
    find_valleys(thr = thresh * ncol(small), invert = invert) %>%
    mutate_at(vars(-n), funs(. * 10)) %>%
    rename_(plate_y = ~mid, plate_col = ~n, rough_t = ~left, rough_b = ~right)

  # Generate all combinations of detected rows and columns
  expand.grid(rows$plate_row, cols$plate_col) %>%
    rename_(plate_row = ~Var1, plate_col = ~Var2) %>%
    left_join(rows, by = 'plate_row') %>%
    left_join(cols, by = 'plate_col') %>%
    mutate_(
      # Add padding if desired
      rough_l = ~rough_l - pad[1],
      rough_r = ~rough_r + pad[2],
      rough_t = ~rough_t - pad[3],
      rough_b = ~rough_b + pad[4],
      # Limit edges if they excede dimensions of image after padding
      rough_l = ~ifelse(rough_l < 1, 1, rough_l),
      rough_r = ~ifelse(rough_r > nrow(img), nrow(img), rough_r),
      rough_t = ~ifelse(rough_t < 1, 1, rough_t),
      rough_b = ~ifelse(rough_b > ncol(img), ncol(img), rough_b)
    ) %>%
    # Remove any detected rough cropped objects that are less than 100x100 pixels
    filter(
      abs(rough_l - rough_r) > 100,
      abs(rough_t - rough_b) > 100
    ) %>%
    mutate(
      position = 1:n(),
      plate_x = as.integer(round(plate_x)),
      plate_y = as.integer(round(plate_y))
    ) %>%
    select_(~position, ~plate_row, ~plate_col, ~plate_x, ~plate_y, ~rough_l, ~rough_r, ~rough_t, ~rough_b)
}


# Determine plate rotation angle
#
# @param img A rough cropped plate image.
# @param rough Rough angle in degrees clockwise with which to rotate plate.
# @param range Rotation range to explore in degrees.
#
#' @importFrom EBImage rotate fillHull dilate makeBrush resize

grid_angle <- function(img, rough, range) {

  small <- EBImage::rotate(EBImage::resize(img, w = 301, h = 301), rough)
  objs <-
    screenmill:::object_features(EBImage::bwlabel(small)) %>%
    dplyr::filter(
      area  < mean(area) + (5 * mad(area)),
      area  > 10,
      eccen < 0.8
    ) %>%
    dplyr::arrange(x, y) %>%
    # Center grid as point of rotation
    dplyr::mutate(
      x = x - 151,
      y = y - 151
    )

  range_deg <- seq(-range / 2, range / 2, by = 0.01)
  range_rad <- range_deg * (pi / 180) # convert to radians
  median_abs_diff <- sapply(range_rad, function(theta) {
    rotated_x <- (objs$x * cos(theta)) - (objs$y * sin(theta))
    sorted <- sort(rotated_x)
    median(abs(diff(sorted)))
  })

  angle <- range_deg[which.min(median_abs_diff)]

  return(rough + angle)
}


# Fine crop plates
#
# Fine crop plates
#
# @param img Image
# @param rotate Rotate
# @param invert Invert
# @param pad Pad

fine_crop <- function(img, rotate, range, pad, invert) {

  # Invert if desired and set lowest intensity pixel to 0
  if (invert) neg <- max(img) - img else neg <- img - min(img)
  norm <- EBImage::normalize(neg, inputRange = c(0.1, 0.8))

  # Be aggressive at detecting objects, use watershed to split circular objects
  thr <-
    EBImage::gblur(norm, sigma = 6) %>%
    EBImage::thresh(w = 20, h = 20, offset = 0.01)

  # Determine rotation angle and rotate plate
  angle   <- screenmill:::grid_angle(thr, rotate, range = range)
  rotated <- EBImage::rotate(thr, angle)

  # obj <- EBImage::bwlabel(rotated)
  obj <- EBImage::watershed(EBImage::distmap(rotated))

  # Calculate object features, identify dubious objects and remove them
  feat <- screenmill:::object_features(obj)
  crap <-
    with(feat, feat[
      area  > mean(area) + (5 * mad(area)) |
        area  < 10 |
        eccen > 0.8,
      ])
  good  <- with(feat, feat[!(obj %in% crap$obj), ])
  clean <- EBImage::rmObjects(obj, crap$obj) > 0

  # If fewer than 20 good objects then use default rotation and no fine-crop
  if (nrow(good) < 20) {
    default <-
      data_frame(
        rotate = rotate,
        fine_l = 1, fine_r = ncol(clean), fine_t = 1, fine_b = nrow(clean)
      )
    return(default)
  }


  # Identify edges of grid
  cols <- screenmill:::grid_breaks(clean, 'col', thresh = 0.3)
  if (length(cols) == 0L) cols <- c(1, nrow(clean)) # don't crop
  if (length(cols) == 1L) {
    if (cols > nrow(clean) / 2) {
      cols <- c(1, cols)
    } else {
      cols <- c(cols, nrow(clean))
    }
  }
  rows <- screenmill:::grid_breaks(clean, 'row', thresh = 0.3)
  if (length(rows) == 0L) rows <- c(1, ncol(clean)) # don't crop
  if (length(rows) == 1L) {
    if (rows > ncol(clean) / 2) {
      rows <- c(1, rows)
    } else {
      rows <- c(rows, ncol(clean))
    }
  }

  # Construct fine crop data
  dplyr::data_frame(
    rotate = angle,
    # Adjust edges based on previous dilation and user specified padding
    left   = head(cols, 1) - pad[1],
    right  = tail(cols, 1) + pad[2],
    top    = head(rows, 1) - pad[3],
    bot    = tail(rows, 1) + pad[4]
  ) %>%
    dplyr::mutate_(
      # Limit edges if they excede dimensions of image after padding
      fine_l = ~ifelse(left < 1, 1, left),
      fine_r = ~ifelse(right > nrow(rotated), nrow(rotated), right),
      fine_t = ~ifelse(top < 1, 1, top),
      fine_b = ~ifelse(bot > ncol(rotated), ncol(rotated), bot),
      # Expand edges if fine cropping was too aggressive
      fine_l = ~ifelse(fine_l > 150, 150, fine_l),
      fine_t = ~ifelse(fine_t > 150, 150, fine_t),
      fine_r = ~ifelse(fine_r < nrow(rotated) - 150, nrow(rotated) - 150, fine_r),
      fine_b = ~ifelse(fine_b < ncol(rotated) - 150, ncol(rotated) - 150, fine_b)
    ) %>%
    dplyr::select_(~rotate, ~dplyr::matches('fine'))
}



# Compute Object Features
# Adapted from \link[EBImage]{computeFeatures}

object_features <- function(img) {

  # Get labeled object image matrix (img should be result of EBImage::bwlabel)
  m <- EBImage::imageData(img)

  # Compute size features based on object contour
  radii <-
    EBImage::ocontour(m) %>%
    lapply(as.data.frame) %>%
    bind_rows(.id = 'obj') %>%
    mutate_(obj = ~as.integer(obj)) %>%
    group_by(obj) %>%
    mutate_(radius = ~sqrt((V1 - mean(V1))^2 + (V2 - mean(V2))^2)) %>%
    summarise_(
      perimeter   = ~n(),
      radius_mean = ~mean(radius),
      radius_min  = ~min(radius),
      radius_max  = ~max(radius)
    )

  # Split object indices
  z  <- which(as.integer(m) > 0L)
  objs <- split(z, m[z])

  # Number of pixels in each object
  m00 <- sapply(objs, length)

  # Row sums
  w   <- row(m) * 1
  m10 <- sapply(objs, function(z) sum(w[z]))

  # Col sums
  w   <- col(m) * 1
  m01 <- sapply(objs, function(z) sum(w[z]))

  # Row bias
  w   <- (row(m)^2) * 1
  m20 <- sapply(objs, function(z) sum(w[z]))

  # Col bias
  w   <- (col(m)^2) * 1
  m02 <- sapply(objs, function(z) sum(w[z]))

  w   <- (col(m) * row(m)) * 1
  m11 <- sapply(objs, function(z) sum(w[z]))

  x  <- m10 / m00
  y  <- m01 / m00
  nn <- nearestNeighbor(x, y)

  data_frame(
    obj   = 1:length(objs),
    x     = x,
    y     = y,
    area  = m00,
    mu20  = m20 / m00 - x^2,
    mu02  = m02 / m00 - y^2,
    mu11  = m11 / m00 - x * y,
    det   = sqrt(4 * mu11^2 + (mu20 - mu02)^2),
    theta = atan2(2 * mu11, (mu20 - mu02)) / 2,
    major = sqrt((mu20 + mu02 + det) / 2) * 4,
    minor = sqrt((mu20 + mu02 - det) / 2) * 4,
    eccen = sqrt(1 - minor^2 / major^2),
    ndist = nn$dist,
    nwhich = nn$which
  ) %>%
    left_join(radii, by = 'obj') %>%
    select_(~obj, ~x, ~y, ~area, ~perimeter, ~radius_mean, ~radius_max,
            ~radius_min, ~eccen, ~theta, ~major, ~minor, ~ndist, ~nwhich)
}


# Determine column or row breaks for grid
#
# Uses midpoints of low average pixel intensity to determine column breaks.
#
# @param img An Image object or a matrix
# @param type Type of grid breaks ('column' or 'row') defaults to column.
# @param thresh Threshold used to define local valleys in image.
# @param edges How to handle edge breaks. Defaults to 'inner' which will use
#   the inner edge of flanking valleys. 'outer' will use outer edge of flanking
#   valleys. Otherwise the midpoint of flanking valleys will be returned.

grid_breaks <- function(img, type = c('col', 'row'), thresh = 0.03, edges = c('inner', 'outer', 'mid')) {

  if (grepl('col', type[1], ignore.case = T)) {
    # Rows of matrix correspond to x axis (i.e. columns)
    valleys <- find_valleys(rowSums(img), thr = thresh * nrow(img))
  } else if (grepl('row', type[1], ignore.case = T)) {
    # Columns of matrix correspond to y axis (i.e. rows)
    valleys <- find_valleys(colSums(img), thr = thresh * ncol(img))
  }

  if (edges[1] == 'inner') {
    # Use right edge of first valley, left of last, otherwise use midpoint
    breaks <-
      mutate(
        valleys,
        breaks = ifelse(mid == first(mid), right,
                        ifelse(mid == last(mid), left, mid))
      )
  } else if (edges[1] == 'outer') {
    # Use left edge of first valley, right of last, otherwise use midpoint
    breaks <-
      mutate(
        valleys,
        breaks = ifelse(mid == first(mid), left,
                        ifelse(mid == last(mid), right, mid))
      )
  } else {
    breaks <- mutate(valleys, breaks = mid)
  }
  return(breaks$breaks)
}


# Label continuous runs with an integer beginning with 1
label_runs <- function(x) {
  runs <- rle(x)$lengths
  rep.int(1:length(runs), runs)
}


# Find the midpoint, left, and right edge of regions of continuous low values
find_valleys <- function(y, thr, invert = F) {

  # Identify and label valleys
  is_peak <- y > thr
  if (invert) is_peak <- !is_peak # Invert peak definition if desired
  regions <- label_runs(is_peak)  # Label consecutive low (F) or high (T) runs
  regions[is_peak] <- 0           # Label peak regions as 0
  valleys <- unique(regions)
  valleys <- valleys[which(valleys != 0)]

  if (length(valleys) < 1) {
    return(data_frame(left = numeric(), mid = numeric(), right = numeric()))
  }

  # Find left, middle, and right edge of valley
  bind_rows(
    lapply(valleys, function(v) {
      x <- which(regions == v)
      data_frame(left = min(x), mid = mean(x), right = max(x))
    })
  ) %>%
    mutate(n = 1:n())
}


# Read an image in greyscale
read_greyscale <- function(path, invert = FALSE) {
  img <- EBImage::readImage(path)
  if (EBImage::colorMode(img)) {
    img <- EBImage::channel(img, 'luminance')
  }
  img <- EBImage::imageData(img)
  if (invert) img <- 1 - img
  return(img)
}
