% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/wbs-helper.R
\name{signed_contrast}
\alias{signed_contrast}
\title{Wrapper for \code{cusum()}, to produce /signed/ cusum (unsigned means that
the < contrast , y> is manually made to be positive, and signed means it retains its original
sign) contrast given \code{s,b,e} as start, break and end.}
\usage{
signed_contrast(s, b, e, n = NULL, y)
}
\arguments{
\item{s}{starting index.}

\item{b}{breakpoint index.}

\item{e}{end index.}

\item{y}{data.}
}
\description{
Wrapper for \code{cusum()}, to produce /signed/ cusum (unsigned means that
the < contrast , y> is manually made to be positive, and signed means it retains its original
sign) contrast given \code{s,b,e} as start, break and end.
}
