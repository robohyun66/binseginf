#' P-values for post-selection inference
#'
#' @param y numeric vector
#' @param polyhedra polyhedra object
#' @param contrast contrast numeric vector
#' @param sigma numeric to denote the sd of the residuals
#' @param null_mean the null-hypothesis mean to test against
#' @param alternative string of either "one.sided" or "two.sided" for the
#' alternative. If one.sided, the alternative means the test statistic is positive.
#' @param precBits precision of Rmpfr
#'
#' @return a numeric p-value between 0 and 1
#' @export
pvalue <- function(y, polyhedra, contrast, sigma = 1, null_mean = 0,
  alternative = c("one.sided", "two.sided"), precBits = NA){

  alternative <- match.arg(alternative, c("one.sided", "two.sided"))

  terms <- .compute_truncGaus_terms(y, polyhedra, contrast, sigma)

  res <- sapply(null_mean, function(x){.truncated_gauss_cdf(terms$term, mu = x,
    sigma = terms$sigma, a = terms$a, b = terms$b, precBits = precBits)})

  if(alternative == "one.sided") res else 2*min(res, 1-res)
}

.compute_truncGaus_terms <- function(y, polyhedra, contrast, sigma){
  z <- as.numeric(contrast %*% y)

  vv <- contrast %*% contrast
  sd <- as.numeric(sigma*sqrt(vv))

  rho <- as.numeric(polyhedra$gamma %*% contrast) / vv
  vec <- as.numeric((polyhedra$u - polyhedra$gamma %*% y + rho * z)/rho)

  if(any(rho > 0)) vlo <- max(vec[rho > 0]) else vlo <- -Inf
  if(any(rho < 0)) vup <- min(vec[rho < 0]) else vup <- Inf

  list(term = z, sigma = sd, a = vlo, b = vup)
}

.truncated_gauss_cdf <- function(value, mu, sigma, a, b, tol_prec = 1e-2, precBits = NA){
  if(b < a) stop("b must be greater or equal to a")

  val <- numeric(length(value))
  val[value <= a] <- 0
  val[value >= b] <- 1
  idx <- intersect(which(value >= a), which(value <= b))
  if(length(idx) == 0) return(val)

  a_scaled <- (a-mu)/sigma; b_scaled <- (b-mu)/sigma
  z_scaled <- (value[idx]-mu)/sigma
  denom <- stats::pnorm(b_scaled) - stats::pnorm(a_scaled)
  numerator <- stats::pnorm(b_scaled) - stats::pnorm(z_scaled)

  val[idx] <- numerator/denom

  #fix any NAs first
  issue <- any(is.na(val[idx]) | is.nan(val[idx]))
  if(any(issue)) val[idx[issue]] <- .truncated_gauss_cdf_Rmpfr(value[idx[issue]],
                                                                                  mu, sigma, a, b, 10)

  #fix any source of possible imprecision
  issue <- any(denom < tol_prec) | any(numerator < tol_prec) |
    any(val[idx] < tol_prec) | any(val[idx] > 1-tol_prec)

  if(any(issue) & !is.na(precBits)) val[idx[issue]] <- .truncated_gauss_cdf_Rmpfr(value[idx[issue]],
                                                               mu, sigma, a, b, precBits)

  val
}

.truncated_gauss_cdf_Rmpfr <- function(value, mu, sigma, a, b, tol_zero = 1e-5,
                                       precBits = 10){

  a_scaled <- Rmpfr::mpfr((a-mu)/sigma, precBits = precBits)
  b_scaled <- Rmpfr::mpfr((b-mu)/sigma, precBits = precBits)
  z_scaled <- Rmpfr::mpfr((value-mu)/sigma, precBits = precBits)

  denom <- Rmpfr::pnorm(b_scaled) - Rmpfr::pnorm(a_scaled)
  if(denom < tol_zero) denom <- tol_zero
  as.numeric(Rmpfr::mpfr((Rmpfr::pnorm(b_scaled) - Rmpfr::pnorm(z_scaled))/denom, precBits = precBits))
}




##' Added from selectiveInference package.
##' @export
poly.pval <- function(y, G, u, v, sigma, bits=NULL) {
  z = sum(v*y)
  vv = sum(v^2)
  sd = sigma*sqrt(vv)

  rho = G %*% v / vv
  vec = (u - G %*% y + rho*z) / rho
  vlo = suppressWarnings(max(vec[rho>0]))
  vup = suppressWarnings(min(vec[rho<0]))

  pv = tnorm.surv(z,0,sd,vlo,vup,bits)
  return(list(pv=pv,vlo=vlo,vup=vup, vty=z))
}


##' Added from selectiveInference package.
tnorm.surv <- function(z, mean, sd, a, b, bits=NULL){

    z = max(min(z,b),a)

    # Check silly boundary cases
    p = numeric(length(mean))
    p[mean==-Inf] = 0
    p[mean==Inf] = 1
  
    # Try the multi precision floating point calculation first
    o = is.finite(mean)
    mm = mean[o]
    pp = mpfr.tnorm.surv(z,mm,sd,a,b,bits)
  
    # If there are any NAs, then settle for an approximation
    oo = is.na(pp)
    ## if(any(oo))browser()
    if (any(oo)) pp[oo] = bryc.tnorm.surv(z,mm[oo],sd,a,b)
  
    p[o] = pp
    return(p)
}



##' Temporarily added from selectiveInference package.
##' Returns Prob(Z>z | Z in [a,b]), where mean can be a vector, using
##' multi precision floating point calculations thanks to the Rmpfr package
mpfr.tnorm.surv <- function(z, mean=0, sd=1, a, b, bits=NULL) {
    # If bits is not NULL, then we are supposed to be using Rmpf
    # (note that this was fail if Rmpfr is not installed; but
    # by the time this function is being executed, this should
    # have been properly checked at a higher level; and if Rmpfr
    # is not installed, bits would have been previously set to NULL)
    if (!is.null(bits)) {
      z = Rmpfr::mpfr((z-mean)/sd, precBits=bits)
      a = Rmpfr::mpfr((a-mean)/sd, precBits=bits)
      b = Rmpfr::mpfr((b-mean)/sd, precBits=bits)
      return(as.numeric((Rmpfr::pnorm(b)-Rmpfr::pnorm(z))/
                        (Rmpfr::pnorm(b)-Rmpfr::pnorm(a))))
    }

    # Else, just use standard floating point calculations
    z = (z-mean)/sd
    a = (a-mean)/sd
    b = (b-mean)/sd
    numer = (stats::pnorm(b)-stats::pnorm(z))
    denom = (stats::pnorm(b)-stats::pnorm(a))
    pv = numer/denom
    return(pv)
}



##' A numerical approximation, to be used as a substitute for
##' \code{mpfr.tnorm.surv()}.
bryc.tnorm.surv <- function(z, mean=0, sd=1, a, b) {
  z = (z-mean)/sd
  a = (a-mean)/sd
  b = (b-mean)/sd
  n = length(mean)

  term1 = exp(z*z)
  o = a > -Inf
  term1[o] = ff(a[o])*exp(-(a[o]^2-z[o]^2)/2)
  term2 = rep(0,n)
  oo = b < Inf
  term2[oo] = ff(b[oo])*exp(-(b[oo]^2-z[oo]^2)/2)
  p = (ff(z)-term2)/(term1-term2)

  # Sometimes the approximation can give wacky p-values,
  # outside of [0,1] ..
  #p[p<0 | p>1] = NA
  p = pmin(1,pmax(0,p))
  return(p)
}

ff <- function(z) {
  return((z^2+5.575192695*z+12.7743632)/
         (z^3*sqrt(2*pi)+14.38718147*z*z+31.53531977*z+2*12.77436324))
}


##' Takes vup, vlo and v and returns list(pv,vlo,vup). Originally from the
##' selectiveInfernece package. Modified to take a polyhedra class object
##' \code{poly}.
##' @param vup vup
##' @param vlo vlo
##' @param v Contrast vector.
##' @param y data vector
##' @param sigma noise level
##' @param bits Number of decimal points for higher precision calculation of
##'     pvalue. (i.e. precision of Rmpfr)
##'
##' @return List of vup, vlo and pv.
##' @export
poly.pval2 <- function(y, poly=NULL, v, sigma, vup=NULL, vlo=NULL, bits=NULL,
                       shift=NULL, ic.poly=NULL) {

    ## Combine polyhedra if necessary.
    if(!is.null(ic.poly)) poly = combine.polyhedra(poly, ic.poly)

    ## Shift polyhedron by a constant \R^n shift if needed
    if(!is.null(shift)){
        stopifnot(length(shift)==length(y))
        poly$u = poly$u - poly$gamma%*%shift
    }

    z = sum(v*y)
    vv = sum(v^2)
    sd = sigma*sqrt(vv)
    Gv = poly$gamma %*% v
    Gy = poly$gamma %*% y
    Gv[which(abs(Gv)<1E-15)] = 0
    rho = Gv / vv
    vec = (poly$u - Gy + rho*z) / rho
    vlo = suppressWarnings(max(vec[rho>0]))
    vup = suppressWarnings(min(vec[rho<0]))
    pv = tnorm.surv(z,0,sd,vlo,vup,bits)
    if(vlo < vup){ flag="go" } else { flag="vlo-vup-reversed" }
    
    return(list(pv=pv,vlo=vlo,vup=vup, flag=flag,
                z=z##temporary
                ))
}



##' If a list of contrast vectors are supplied, use this.
##' @param y data vector.
##' @param poly polyhedra object.
##' @param vlist list of contrast vectors.
##' @param sigma data noise level.
##' @param shift how much additive noise was used in detection.
##' @param bits numerical precision in Gaussian probability mass calculation,
##'     for methods from the Rmpfr package.
##' @return vector of p-values. \code{Inf} are the ones that were not calculated
##' @export
poly_pval2_from_vlist <- function(y, poly, vlist, sigma, shift=NULL, bits=5000, ic.poly=NULL){
    if(!is.null(vlist)){
        pvs = sapply(vlist, function(v){
            return(poly.pval2(y, poly, v, sigma, shift=shift, bits=bits,ic.poly=ic.poly)$pv)
        })
    } else {
        return(c())
    }
}





##' Calculating TG p-value from bootstrapping centered residuals
##' @param y data vector.
##' @param bootmat vector whose rows are bootstrapped y's.
##' @param bootmat.times.v vector of bootmat times y.
##' @param weight if TRUE, returns denominator of TG; if FALSE, returns entire
##'     p-value.
##' @return p-value or weight, depending on \code{weight} input.
poly_pval_bootsub_inner <- function(Vlo, Vup, vty, v, y=NULL, nboot=1000, bootmat=NULL,
                                    weight=FALSE, bootmat.times.v=NULL, adjustmean, pad=FALSE){

    ## if needed, calculate bootstrapped v^T(y^*-\bar y).
    if(is.null(bootmat.times.v)){
        if(is.null(bootmat)){
            assertthat::assert_that(!is.null(y))
            y.centered = y - adjustmean
            n = length(y)
            bootmat = t(sapply(1:nboot, function(iboot){
                y.centered[sample(n, size=n, replace=TRUE)]
            }))
        }
        bootmat.times.v = bootmat %*% v
    }

    ## Calculate the requisite quantities
    vtr = as.numeric(bootmat.times.v)
    padding = (if(pad)1E-4 * n^(-0.25) else 0)
    numer = sum(vtr > as.numeric(vty) & vtr < as.numeric(Vup)) + padding
    denom = sum(vtr > as.numeric(Vlo) & vtr < as.numeric(Vup)) + padding
    if(!weight){  p = numer/denom; return(p) }
    if(weight){  w = denom ; return(w) }
}

##' Calculating TG p-value from bootstrapped residuals
##' @export
poly_pval_bootsub <- function(y, G, v, nboot=1000, bootmat=NULL, bootmat.times.v=NULL,
                              sigma, adjustmean=mean(y), pad=FALSE){

    y.centered = y - adjustmean
    obj = poly.pval(y=y, G=G, v=v, u=rep(0,nrow(G)), sigma=sigma)
    Vlo = obj$vlo
    Vup = obj$vup
    vty = sum(v*y)
    p = poly_pval_bootsub_inner(Vlo, Vup, vty, v, y, nboot=nboot,
                                bootmat=bootmat,
                                bootmat.times.v=bootmat.times.v,
                                adjustmean=adjustmean, pad=pad)
    return(p)
}


##' If a list of contrast vectors are supplied, use this. (large sample size)
poly_pval_bootsub_large_for_vlist <- function(y,G,vlist,nboot,sigma,adjustmean=mean(y)){
    if(!is.null(vlist)){
        pvs = sapply(vlist, function(v){
            poly_pval_bootsub_large(y, G, v, nboot, sigma, adjustmean)
        })
    }
}

##' If a list of contrast vectors are supplied, use this!
poly_pval_bootsub_for_vlist <- function(y,G,vlist,nboot,sigma,adjustmean=mean(y)){
    if(!is.null(vlist)){
        pvs = sapply(vlist, function(v){
            poly_pval_bootsub(y=y, G=G, v=v, nboot=nboot, sigma=sigma,
                              adjustmean=adjustmean)
        })
    }
}


##' Helper function for deleting shorter segments.
ridlong <- function(y.centered, adjustmean){
    n = length(y.centered)
    stopifnot(n == length(adjustmean))
    difference = adjustmean[2:n]-adjustmean[1:(n-1)]
    cp.in.adjustmean = which(abs(difference) > 1E-10)
    segments = make_segment_inds(cp.in.adjustmean, n)
    na.segments = unlist(segments[sapply(segments, length) <= n/4])
    if(!is.null(na.segments)) y.centered = y.centered[-na.segments]
    return(y.centered)
} 

##' For large |nboot|, calculating TG p-value from bootstrapped residuals by
##' chunking into 10000 replicates each. TODO In the future, we want to do /not/
##' repeat the bootstrap for each v, but do it in batch.
##' @param y data vector.
##' @param G Polyhedron gamma matrix.
##' @param v contrast vector
##' @param vlist A list of contrast vectors. If supplied, then v will be
##'     ignored.
##' @param nboot.max The number of bootstraps replicates in total.
##' @export
poly_pval_bootsub_large <- function(y, G, v, nboot.max=100*10000, sigma,
                                    adjustmean=mean(y), pad=FALSE, vlist=NULL,
                                    ridlong=FALSE, stable.thresh=0.01){
    ## Basic checks
    nboot.base = 10000 ## The base number of bootstraps to run in every fold
    nboot = 10*10000
    if(nboot < nboot.base)  stop("Use poly_pval_bootsub() instead of .._large().")
    n = length(y)
    
    ## Get TG quantities
    out = poly.pval(y=y, G=G, v=v, u=rep(0,nrow(G)), sigma=sigma)
    y.centered = y - adjustmean

    ## Process y.centered to eliminate smaller segments, if needed.
    if(ridlong){
        y.centered = ridlong(y.centered, adjustmean)
        if(length(y.centered)==0) return(NULL)
    }

    ## Record (bootmat x v) by doing it |nrep| times separately
    bootmat.times.v.list = list()
    nrep = ceiling(nboot/nboot.base)

    nrep.so.far = 0
    p.so.far = -1 ## This is just a fake starter value
    stable <- function(p, p.so.far){ abs(mean(tail(p.so.far,2))-p) < stable.thresh }
    ## stable <- function(p, p.so.far){abs(linpredict(tail(p.so.far,2))-p) < stable.thresh}
    done = FALSE
    while(!done){
        for(irep in nrep.so.far+(1:nrep)){
            bootmat = t(sapply(1:nboot.base, function(iboot){
                y.centered[sample(length(y.centered), size=n, replace=TRUE)]
            }))
            bootmat.times.v.list[[irep]] = as.numeric(bootmat %*% v)
        }
        all.vty = unlist(bootmat.times.v.list)
        p = poly_pval_bootsub_inner(Vlo=out$vlo, Vup=out$vup, vty=sum(v*y), v,
                                    y, nboot=nboot.base,
                                    bootmat.times.v=all.vty,
                                    adjustmean=adjustmean, pad=pad)
        
        ## if(!is.nan(p) & stable(p, p.so.far)) done=TRUE
        reach.max.nrep = (length(all.vty) > nboot.max)
        pv.is.okay = (!is.nan(p) & stable(p, p.so.far))
        if(pv.is.okay | reach.max.nrep) done=TRUE
        p.so.far = c(p.so.far, p)
        nrep.so.far = nrep.so.far + nrep
    }
    return(p)
}

pval_plugin = poly_pval_bootsub_inner
pval_plugin_wrapper = poly_pval_bootsub


##' Wrapper to *only* do the premultiply option for plain TG inference..
##' @param y data vector
##' @param v contrast vector
##' @param obj output from running an algorithm *before* adding polyhedra information.
poly_pval_premultiply <- function(y=y, v=v, obj=obj, sigma=sigma){
    pv = randomize_addnoise(y=y, v=v, sigma=sigma,
                            inference.type="pre-multiply", sigma.add=0,
                            orig.fudged.obj=obj, bits=5000)$pv
    return(pv)
}


##' Computes TG p-value and related objects (vlo,vup,vty,denom,numer) in the
##' case that Gy and Gv are pre-calculated; the option
##' inference.type="pre-multiply".
##' @param Gy G times y
##' @param Gv G times v
##' @param v constrast vector
##' @param y data
##' @param sigma noise level
##' @param bits number of precision bits used for calculation of Gaussian
##'     tails. Roughly 3*bits is the /number/ of digits that is being used.
##' @return list containing pv,vlo,vup,vty,denom,numer.
poly_pval_from_inner_products <- function(Gy, Gv, v,y,sigma,u,bits=1000, warn=TRUE){

    ## Rounding ridiculously small numbers
    Gv[which(abs(Gv)<1E-15)] = 0

    vy = sum(v*y)
    vv = sum(v^2)
    sd = sigma*sqrt(vv)

    rho = Gv / vv
    vec = (u - Gy + rho*vy) / rho
    vlo = suppressWarnings(max(vec[rho>0]))
    vup = suppressWarnings(min(vec[rho<0]))
    vy = max(min(vy, vup),vlo)

    z = Rmpfr::mpfr( vy/sd, precBits=bits)
    a = Rmpfr::mpfr(vlo/sd, precBits=bits)
    b = Rmpfr::mpfr(vup/sd, precBits=bits)
    
    if(!(a<=z &  z<=b) & warn){
        warning("F(vlo)<vy<F(vup) was violated, in partition_TG()!")
        ## print("F(vlo)<vy<F(vup) was violated, in partition_TG()!")
    }
    numer = as.numeric((Rmpfr::pnorm(b)-Rmpfr::pnorm(z)))
    denom = as.numeric((Rmpfr::pnorm(b)-Rmpfr::pnorm(a)))
    pv = as.numeric(numer/denom)
    return(list(denom=denom, numer=numer, pv = pv, vlo=vlo, vty=vy, vy=vy, vup=vup,
                sigma=sigma))
}



##' One-sided z-test regarding $v^Tmu$, using $v^Ty$.
##' @param y data vector
##' @param v contrast vector
##' @param sigma noise standard deviation
##' @export
ztest <- function(y, v, sigma=1){
    sigma.v = sigma * sqrt(sum(v * v))
    vty = sum(v * y)
    pv = 1 - Rmpfr::pnorm(vty, mean=0, sd = sigma.v)
    return(pv)
}





##' From polyhedron and data vector and contrast, gets the probability of vtY
##' larger than v^Ty , conditional on the orthogonal projection on v.
##' @param y data
##' @param poly polyhedra object produced form \code{polyhedra(wbs_object)}
##' @param sigma data noise (standard deviation)
##' @param nullcontrast the null value of \eqn{v^T\mu}, for \eqn{\mu = E(y)}.
##' @param v contrast vector
##'
##' @return list of two vectors: denominators and numerators, each named
##'     \code{denom} and \code{numer}.
partition_TG <- function(y, poly, v, sigma, nullcontrast=0, bits=50, reduce,
                         shift=NULL, ic.poly=NULL, warn=TRUE){

    ## Basic checks
    stopifnot(length(v)==length(y))

    vy = sum(v*y)
    vv = sum(v^2)
    sd = sigma*sqrt(vv)

    ## Shift polyhedron by a constant \R^n shift if needed
    if(!is.null(shift)){
        stopifnot(length(shift)==length(y))
        poly$u = poly$u - poly$gamma%*%shift
    }

    ## Add stopping component to the polyhedron at this point, if needed
    if(!is.null(ic.poly)){
        poly$gamma = rbind(poly$gamma, ic.poly$gamma)
        poly$u = c(poly$u, ic.poly$u)
    }

    pvobj <- poly.pval2(y, poly, v, sigma)
    vup = pvobj$vup
    vlo = pvobj$vlo
    vy = max(min(vy, vup),vlo)
    
    ## Make it so that vlo<vup is ensured (maybe not here..)
    ## if(vlo >= vup) stop("vlo < vup must hold.")
    ## if(vlo >= vup) return("vlo < vup must hold.")

    ## Calculate a,b,z for TG = (F(b)-F(z))/(F(b)-F(a))
    z = Rmpfr::mpfr(vy/sd, precBits=bits)
    a = Rmpfr::mpfr(vlo/sd, precBits=bits)
    b = Rmpfr::mpfr(vup/sd, precBits=bits)
    if(!(a<=z &  z<=b) & warn){
        warning("F(vlo)<vy<F(vup) was violated, in partition_TG()!")
    }

    ## Separately store and return num&denom of TG
    numer = as.numeric(Rmpfr::pnorm(b)-Rmpfr::pnorm(z))
    denom = as.numeric(Rmpfr::pnorm(b)-Rmpfr::pnorm(a))

    ## Form p-value as well.
    pv = as.numeric(numer/denom)
    ## if(!(0 <= pv & pv <= 1)) print("pv was not between 0 and 1, in partition_TG()!")

    return(list(denom=denom, numer=numer, pv=pv, vlo=vlo, vy=vy, vup=vup,
                flag=pvobj$flag))
}

