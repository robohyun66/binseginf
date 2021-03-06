#' Binary segmentation with fixed steps

#' y must not have duplicated values. This is to avoid
#' degenerate behavior of binary segmentation
#'
#' @param y numeric vector to contain data
#' @param numSteps numeric of number of steps
#' @param sigma.add is the amount (standard deviation) of i.i.d. Gaussian noise
#'     added to the data.
#' @param y.addnoise Manully inputted additive noise. Defaults to \code{NULL}.
#'
#' @return a bsfs object, which is a list of information regarding the fitted
#'     algorithm. The list component \code{y} is the data used for actual
#'     fitting; \code{y} is the pre-noise original data; \code{y.addnoise}
#'     (if not null) is the added noise.
#' @export
bsfs <- function(y, numSteps, sigma.add=NULL, numIntervals=NULL, ic.stop=FALSE, y.addnoise=NULL){

    ## Basic checks
    if(numSteps >= length(y)) stop("numSteps must be strictly smaller than the length of y")
    if(numSteps <= 0) step("numSteps must be at least 1.")
    if(!is.null(numIntervals)) warning("You provided |numIntervals| but this will not be used.")
    y.orig = y
    if(!is.null(y.addnoise) & is.null(sigma.add))  stop("Provide |sigma.add|.")
    if(!is.null(sigma.add)){
        if(is.null(y.addnoise)){
            y.addnoise = rnorm(length(y), 0, sigma.add)
        }
        y = y + y.addnoise
    }

    # Initialization
    n <- length(y); tree <- .create_node(1, n)
    cp <- c()

    for(steps in 1:numSteps){
      leaves.names <- .get_leaves_names(tree)
      for(i in 1:length(leaves.names)){
        leaf <- data.tree::FindNode(tree, leaves.names[i])

        res <- .find_breakpoint(y, leaf$start, leaf$end)

        leaf$breakpoint <- res$breakpoint; leaf$cusum <- res$cusum
      }

      node.name <- .find_leadingBreakpoint(tree)
      node.selected <- data.tree::FindNode(tree, node.name)
      node.selected$active <- steps
      node.pairs <- .split_node(node.selected)
      node.selected$AddChildNode(node.pairs$left)
      node.selected$AddChildNode(node.pairs$right)
    }

    y.fit <- .refit_binseg(y, jumps(tree))
    obj <- structure(list(tree = tree, y.fit = y.fit, numSteps = numSteps), class = "bsfs")
    cp <- jumps(obj)
    leaves <- .enumerate_splits(tree)
    cp.sign <- sign(as.numeric(sapply(leaves, function(x){
        data.tree::FindNode(tree, x)$cusum})))
    obj <- structure(list(tree = tree, y.fit = y.fit, numSteps = numSteps, cp = cp,
                          cp.sign=cp.sign, y=y, y.orig=y.orig, noisy=FALSE), class = "bsfs")
    obj$y.orig = y.orig

    ## If applicable, collect IC stoppage information
    obj$ic.stop = ic.stop
    if(ic.stop){

        ## Obtain IC information
        ic_obj = get_ic(obj$cp, obj$y, 2, sigma)
        obj$stoptime = ic_obj$stoptime
        obj$consec = consec
        obj$ic_poly = ic_obj$poly
        obj$ic_flag = ic_obj$flag
        obj$ic_obj = ic_obj

        ## Update changepoints with stopped model
        obj$cp.all = obj$cp
        obj$cp.sign.all = obj$cp.sign
        if(ic_obj$flag=="normal"){
            obj$cp = obj$cp[1:obj$stoptime]
            obj$cp.sign = obj$cp.sign[1:obj$stoptime]
        } else {
            obj$cp = obj$cp.sign = c()
        }
    }


  if(!is.null(sigma.add) | !is.null(y.addnoise) ){
      obj$sigma.add = sigma.add
      obj$y.addnoise = y.addnoise
      obj$noisy = TRUE
  }
  
  return(obj)
}

#' is_valid for bsfs
#'
#' @param obj bsfs object
#'
#' @return TRUE if valid
#' @export
is_valid.bsfs <- function(obj){
  if(class(obj$tree)[1] != "Node") stop("obj$tree must a Node")
  if(!is.numeric(obj$numSteps)) stop("obj$numSteps must be a numeric")
  if(length(.enumerate_splits(obj$tree)) != obj$numSteps)
    stop("obj$tree and obj$numSteps disagree")

  TRUE
}

#' Get jumps from bsfs objects
#'
#' Enumerates the jumps. Sorted = F will return the jumps in order
#' of occurance in the binSeg algorithm. Sorted = T will list the jumps
#' in numeric order
#'
#' @param obj bsfs object
#' @param sorted boolean
#' @param ... not used
#'
#' @return vector of jumps
#' @export
jumps.bsfs <- function(obj, sorted = F, ...){
  jumps(obj$tree, sorted)
}

#' Get the cusum for jumps for bsfs objects
#'
#' Enumerates the cusum for each jump. Sorted = F will return the jumps in order
#' of occurance in the binSeg algorithm. Sorted = T will list the jumps
#' in numeric order
#'
#' @param obj  bsfs object
#' @param sorted  boolean
#' @param ... not use
#'
#' @return vector of cusum numerics
#' @export
jump_cusum.bsfs <- function(obj, sorted = F, ...){
  jump_cusum(obj$tree, sorted)
}

##' Summary of bsfs object
##'
##' @param object  bsfs object
##' @param ... not used
##'
##' @return matrix of summary statistics
##' @export
summary.bsfs <- function(object, ...){
  summary(object$tree)
}

.refit_binseg <- function(y, jumps){
  stopifnot(max(jumps) < length(y), min(jumps) > 0)
  stopifnot(all(jumps %% 1 == 0), length(jumps) == length(unique(jumps)))

  n <- length(y); y.fit <- numeric(n)
  jumps <- c(0, sort(jumps), n)
  for(i in 2:length(jumps)){
    y.fit[(jumps[i-1]+1):jumps[i]] <- mean(y[(jumps[i-1]+1):jumps[i]])
  }

  y.fit
}

.find_breakpoint <- function(y, start, end){
  ## stopifnot(!any(duplicated(y)))
  if(start > end) stop("start must be smaller than or equal to end")
  if(start == end) return(list(breakpoint = start, cusum = 0))

  breakpoint <- seq(from = start, to = end - 1, by = 1)
  cusum.vec <- sapply(breakpoint, .cusum, y = y, start = start, end = end)

  idx <- which.max(abs(cusum.vec))
  list(breakpoint = breakpoint[idx], cusum = cusum.vec[idx])
}

.cusum <- function(y, start, idx, end){
  v <- .cusum_contrast(start, idx, end)
  as.numeric(v %*% y[start:end])
}

#n1 is denoted as start to idx (inclusive)
.cusum_contrast <- function(start, idx, end){
  if(start > idx) stop("start must be smaller or equal than idx")
  if(idx >= end) stop("idx must be smaller to end")

  n1 <- idx - start + 1
  n2 <- end - idx

  c(rep(-1/n1, n1), rep(1/n2, n2)) * sqrt(1/((1/n1) + (1/n2)))
}

.cusum_contrast_full <- function(start, idx, end, n){
  res <- rep(0, n)
  res[start:end] <- .cusum_contrast(start, idx, end)

  res
}


##' Print function for convenience, of |wbs| class object.
##' @export
print.bsfs <- function(obj){
    cat("Detected changepoints using BS with", obj$numSteps, "steps is", obj$cp * obj$cp.sign, fill=TRUE)
    if(!is.null(obj$pvs)){
        ## cat("Pvalues of", obj$cp * obj$cp.sign [ 1:obj$numSteps], "are", obj$pvs, fill=TRUE)
        cat("Pvalues of", names(obj$pvs), "are", obj$pvs, fill=TRUE)
    }
}

## ##' Returns a reduced object. Really a convenience function than a real
## ##' function, as it is not currently possible to cut the tree
## obj$tree
## snapshot.bsfs <- function(obj, numSteps){

##     ## Basic checks
##     if(is.null(obj$pvs)) stop("Not recommended to use this snapshot of object that hasn't had addpv() applied to it. There's no point!")
##     if(obj$ic.stop) stop("Can't take a snapshot of an IC-stopped |bsfs| object.")
##     if(numSteps > obj){ stop("Can't take a snapshot of a higher number of steps than that of the original |bsfs| object.") }
##     if(numSteps == obj){ return(obj) }
##     assertthat::assert_that(numSteps >= 1)

##     ## The code goes here. Basically, reduce everything to be at numSteps
##     set.seed(0)
##     y = rnorm(10)
##     obj = bsfs(y, 3)
##     obj = addpv(obj, sigma=1)
##     objects(obj)
##     numSteps = 1
##     ## End of temporary

##     ## Extract new things from it.
##     obj.new$cp = obj$cp[1:numSteps]
##     obj.new$cp.sign = obj$cp.sign[1:numSteps]
##     obj$polyhedra

##     ##




##     return(new.obj)
## }


## ## Some tests go here.
## y = rnorm()
## obj = bsfs(y, ...)
## new.obj = snapshot(obj)
## expect_true(is_valid(new.obj))
