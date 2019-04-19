# efa related functions
#
# the lav_model_efa_rotate_x() function was based on a script orginally
# written by Florian Scharf (Muenster university, Germany)

# rotate solution
lav_model_efa_rotate <- function(lavmodel = NULL, lavoptions = NULL) {

    if(lavmodel@nefa == 0L || lavoptions$rotation == "none") {
        return(lavmodel)
    }

    # extract unrorated parameters from lavmodel
    x.orig <- lav_model_get_parameters(lavmodel, type = "free", extra = FALSE)

    # rotate
    x.rot <- lav_model_efa_rotate_x(x = x.orig, lavmodel = lavmodel,
                                    lavoptions = lavoptions, extra = FALSE)

    # place rotated parameters back in lavmodel
    lavmodel <- lav_model_set_parameters(lavmodel = lavmodel, x = x.rot)

    # return updated lavmodel
    lavmodel
}

# lower-level function, needed for numDeriv
lav_model_efa_rotate_x <- function(x, lavmodel = NULL, lavoptions = NULL,
                                   ov.var = NULL, extra = FALSE,
                                   type = "free") {

    # extract rotation options from lavoptions
    method <- lavoptions$rotation
    if(method == "none") {
        return(x)
    }
    ropts <- lavoptions$rotation.args

    # place parameters into model matrices
    lavmodel.orig <- lav_model_set_parameters(lavmodel, x = x)

    # GLIST
    GLIST <- lavmodel.orig@GLIST

    # H per group
    H <- vector("list", lavmodel@ngroups)

    # for now, rotate per group (not per block)
    for(g in seq_len(lavmodel@ngroups)) {

        # select model matrices for this group
        mm.in.group <- seq_len(lavmodel@nmat[g]) + cumsum(c(0,lavmodel@nmat))[g]
        MLIST <- GLIST[ mm.in.group ]

        # general rotation matrix (all latent variables)
        H[[g]] <- Hg <- diag( ncol(MLIST$lambda) )
        lv.order <- seq_len( ncol(MLIST$lambda) )

        # fill in optimal rotation for each set
        for(set in seq_len(lavmodel@nefa)) {

            # which ov/lv's are involved in this set?
            ov.idx <- lavmodel@ov.efa.idx[[g]][[set]]
            lv.idx <- lavmodel@lv.efa.idx[[g]][[set]]

            # empty set?
            if(length(ov.idx) == 0L) {
                next
            }

            # just 1 factor?
            if(length(lv.idx) < 2L) {
                next
            }

            # extract unrotated 'A' part from LAMBDA for this 'set'
            A <- MLIST$lambda[ov.idx, lv.idx, drop = FALSE]

            # std.ov? we use diagonal of Sigma for this set of ov's only
            if(ropts$std.ov) {
                if(is.null(ov.var)) {
                    THETA <- MLIST$theta[ov.idx, ov.idx, drop = FALSE]
                    Sigma <- tcrossprod(A) + THETA
                    this.ov.var <- diag(Sigma)
                } else {
                    this.ov.var <- ov.var[[g]][ov.idx]
                }
            } else {
                this.ov.var <- NULL
            }

            # rotate
            res <- lav_matrix_rotate(A           = A,
                                     orthogonal  = ropts$orthogonal,
                                     method      = method,
                                     method.args = list(
                                         geomin.epsilon = ropts$geomin.epsilon,
                                         orthomax.gamma = ropts$orthomax.gamma,
                                         cf.gamma       = ropts$orthomax.gamma,
                                         oblimin.gamma  = ropts$oblimin.gamma),
                                     ROT         = NULL,
                                     ROT.check   = FALSE,
                                     rstarts     = ropts$rstarts,
                                     row.weights = ropts$row.weights,
                                     std.ov      = ropts$std.ov,
                                     ov.var      = this.ov.var,
                                     verbose     = ropts$verbose,
                                     warn        = ropts$warn,
                                     algorithm   = ropts$algorithm,
                                     frob.tol    = ropts$tol,
                                     max.iter    = ropts$max.iter)

            # extract rotation matrix (note, in Asp & Muthen, 2009; this is H')
            H.efa <- res$ROT

            # fill in optimal rotation for this set
            Hg[lv.idx, lv.idx] <- H.efa

            # keep track of possible re-orderings
            lv.order[ lv.idx ] <- lv.idx[res$order.idx]
        } # set

        # rotate all the SEM parameters

        # rotate lambda
        MLIST$lambda <- t(solve(Hg, t(MLIST$lambda)))
        # reorder
        MLIST$lambda <- MLIST$lambda[, lv.order, drop = FALSE]

        # rotate psi (note: eq 22 Asp & Muthen, 2009: transpose reversed)
        MLIST$psi <- t(Hg) %*% MLIST$psi %*% Hg
        # reorder rows
        MLIST$psi <- MLIST$psi[lv.order, , drop = FALSE]
        # reorder cols
        MLIST$psi <- MLIST$psi[, lv.order, drop = FALSE]

        # rotate beta
        if(!is.null(MLIST$beta)) {
            MLIST$beta <- t(Hg) %*% t(solve(Hg, t(MLIST$beta)))
            # reorder rows
            MLIST$beta <- MLIST$beta[lv.order, , drop = FALSE]
            # reorder cols
            MLIST$beta <- MLIST$beta[, lv.order, drop = FALSE]
        }

        # rotate alpha
        if(!is.null(MLIST$alpha)) {
            MLIST$alpha <- t(Hg) %*% MLIST$alpha
            # reorder rows
            MLIST$alpha <- MLIST$alpha[lv.order, , drop = FALSE]
        }

        # no need for rotation: nu, theta

        # store rotated matrices in GLIST
        GLIST[ mm.in.group ] <- MLIST

        # store rotation matrix
        H[[g]] <- Hg

    } # group

    # extract all rotated parameter estimates
    x.rot <- lav_model_get_parameters(lavmodel, GLIST = GLIST, type = type)

    # extra?
    if(extra) {
        attr(x.rot, "extra") <- list(H = H)
    }

    # return rotated parameter estimates as a vector
    x.rot
}

