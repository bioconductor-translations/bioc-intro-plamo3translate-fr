#!/usr/bin/env Rscript
# Build the translated lesson with the installed Carpentries Workbench packages.
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--help" %in% args) {
    cat("Usage: Rscript scripts/build.R [--rebuild]\n")
    return(invisible(NULL))
  }
  if (length(setdiff(args, "--rebuild"))) stop("Unknown build argument")
  script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(script) != 1L) stop("Run this script with Rscript")
  root <- dirname(dirname(normalizePath(script, mustWork = TRUE)))

  # LC_ALL=C.UTF-8 prevents gettext from selecting the French theme strings.
  # This affects this build process only; no shell or system settings are changed.
  Sys.unsetenv("LC_ALL")
  packages <- c("sandpaper", "rmarkdown", "varnish", "jsonlite")
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Missing R packages: ", paste(missing, collapse = ", "))

  pandoc <- rmarkdown::find_pandoc(cache = FALSE)
  usable <- function(p) nzchar(p$dir) && p$version >= "2.11"
  if (!usable(pandoc)) {
    for (dir in c("/Applications/quarto/bin/tools/aarch64",
                  "/Applications/quarto/bin/tools/x86_64",
                  "/Applications/quarto/bin/tools")) {
      if (!file.exists(file.path(dir, "pandoc"))) next
      candidate <- rmarkdown::find_pandoc(cache = FALSE, dir = dir)
      if (usable(candidate)) {
        pandoc <- candidate
        break
      }
    }
  }
  if (!usable(pandoc)) stop("Pandoc 2.11 or newer is required")
  Sys.setenv(RSTUDIO_PANDOC = pandoc$dir)

  readme <- file.path(root, "site", "README.md")
  if (file.exists(readme)) {
    original_readme <- readBin(readme, "raw", n = file.info(readme)$size)
    on.exit({
      dir.create(dirname(readme), recursive = TRUE, showWarnings = FALSE)
      writeBin(original_readme, readme)
    }, add = TRUE)
  }
  previous_options <- options(sandpaper.use_renv = FALSE)
  on.exit(options(previous_options), add = TRUE)

  # Sandpaper currently exposes no citation-processing configuration hook.
  # Wrap its Pandoc arguments in memory, then restore the namespace on exit.
  # No installed package files or global R library contents are modified.
  ns <- asNamespace("sandpaper")
  original_pandoc_args <- get("construct_pandoc_args", ns, inherits = FALSE)
  replace_pandoc_args <- function(fun) {
    unlockBinding("construct_pandoc_args", ns)
    assign("construct_pandoc_args", fun, envir = ns)
    lockBinding("construct_pandoc_args", ns)
  }
  bibliography <- normalizePath(file.path(root, "refs.bib"), mustWork = TRUE)
  replace_pandoc_args(function(path_in, output, to = "html", ...) {
    result <- original_pandoc_args(path_in, output, to, ...)
    if (to %in% c("html", "html4", "html5")) {
      # Resolve citations before lesson.lua transforms challenge/solution divs.
      result$options <- c("--citeproc", paste0("--bibliography=", bibliography),
                          result$options)
    }
    result
  })
  on.exit(replace_pandoc_args(original_pandoc_args), add = TRUE)

  sandpaper::build_lesson(path = root, rebuild = "--rebuild" %in% args,
                         quiet = FALSE, preview = FALSE)

  # Varnish has Incubator branding but stores its matching favicons at asset root.
  assets <- system.file("pkgdown", "assets", package = "varnish")
  icons <- list.files(assets, full.names = TRUE,
                      pattern = "^(favicon|apple-touch-icon|android-chrome|mstile|site[.]webmanifest|safari-pinned-tab)")
  icons <- icons[!file.info(icons)$isdir]
  destination <- file.path(root, "site", "docs", "favicons", "incubator")
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  if (!length(icons) || !all(file.copy(icons, destination, overwrite = TRUE))) {
    stop("Could not copy the bundled favicon assets")
  }
  manifest_path <- file.path(destination, "site.webmanifest")
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
  manifest$icons <- lapply(manifest$icons, function(icon) {
    icon$src <- basename(icon$src)
    icon
  })
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)
  cat("\nBuilt site: ", file.path(root, "site", "docs", "index.html"), "\n", sep = "")
}

main()
