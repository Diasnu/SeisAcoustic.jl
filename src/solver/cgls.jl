"""
    cgls(op, b; <keyword arguments>)
CGLS algorithms for operators whose input and output are files saved on disk

# Arguments
- `op::Function`: linear operator whose forward is called as op(d, m, 1; op_params...) and the adjoint op(m, d, 2; op_params...)
- `b ::String`  : path to oberved data.

# Keyword arguments
- `op_params::NamedTuple=NamedTuple()`: the parameters for the keyword arguments of the linear operator `op`.
- `d_axpby::Function`: compute `y = a*x + b*y` for variables in data space.
- `m_axpby::Function`: compute `y = a*x + b*y` for variables in model space.
- `d_norm::Function` : compute the L2 norm for variables in data space.
- `m_norm::Function` : compute the L2 norm for variables in model space.
- `x0::String="NULL"`      : initial guess of the model parameters.
- `dir_work::String="NULL"`: working directory for the files generated by the linear operator, the directory of pwd() is used if not provided.
- `shift      = 0.0` : trade-off parameter.
- `tol        = 1e-6`: tolerence for convergence.
- `maxIter    = 50`  : maximum number of iterations.
- `print_flag = true`: print the running information.
- `save_flag  = true`: save the intermidiate result of model parameters.

# Improvement
- return the history of iterations
"""
function cgls(op::Function, b::Ts; dir_work::Ts="NULL", op_params::NamedTuple=NamedTuple(),
              d_axpby::Function, m_axpby::Function,  d_norm::Function, m_norm::Function,
              x0::Ts="NULL", shift=0.0, tol=1e-6, maxIter=50, print_flag=true, save_flag=true) where {Ts<:String}

    # determine the working directory2`
    if dir_work == "NULL"
       dir_work =  pwd()
    end

    # create directory for variables in model space
    dir_model = joinpath(dir_work, "cgls_model_space")
    rm(dir_model, force=true, recursive=true)               # clean space
    mkdir(dir_model)
    if !isdir(dir_model)
       error("could not create directory for variables in model space")
    end
    x = joinpath(dir_model, "x.rsf")
    s = joinpath(dir_model, "s.rsf")
    p = joinpath(dir_model, "p.rsf")

    # create directory for variables in data space
    dir_data = joinpath(dir_work, "cgls_data_space")
    rm(dir_data, force=true, recursive=true)                # clean space
    mkdir(dir_data)
    r = joinpath(dir_data, "r"); mkdir(r);
    q = joinpath(dir_data, "q"); mkdir(q);
    if !isdir(dir_data) || !isdir(r) || !isdir(q)
       error("could not create directory of residue")
    end

    # create a directory save the intermidiate result
    if save_flag
       dir_iterations = joinpath(dir_work, "iterations")
       rm(dir_iterations, force=true, recursive=true)        # clean space
       mkdir(dir_iterations)
       if !isdir(dir_iterations)
          error("could not create directory for iterations")
       end
    end

    # initial guess provided
    if x0 != "NULL"

       cp(x0, x, force=true)
       op(r, x, 1; op_params...)
       d_axpby(1.0, b, -1.0, r)                            # r = b - A*x

       op(s, r, 2; op_params...)
       m_axpby(-shift, x, 1.0, s)                          # s = A'*r - shift*x

    # no initial guess
    else

       cp(b, r, force=true)                                # r = b
       op(s, r, 2; op_params...)                           # s = A'*r

       # create x
       hdr = read_RSheader(s)
       write_RSdata(x, hdr, zeros(hdr))                    # (x=0)
    end

    # compute residue
    data_fitting = (d_norm(r))^2                           # ||b-Ax||_2^2
    constraint   = 0.0
    cost0        = data_fitting + constraint
    convergence  = Float64[]; push!(convergence, 1.0);

    # initialize some intermidiate vectors
    cp(s, p, force=true)                                   # p = s

    norms0= m_norm(s)                                      # ||s||_2
    gamma = norms0^2                                       # ||s||_2^2
    normx = m_norm(x)                                      # ||x||_2
    xmax  = normx     # keep the initial one               # ||x||_2
    resNE = 1.0

    gamma0= copy(gamma)                                    # ||s||_2^2
    delta = 0.0

    # iteration counter and stop condition
    k = 0
    run_flag = true

    if print_flag
       header = "  k         data_fitting           constraint             normx                resNE"
       println(""); println(header);
       @printf("%3.0f %20.10e %20.10e %20.10e %20.10e\n", k, data_fitting, constraint, normx, resNE);
    end

    while (k < maxIter) && run_flag

          k = k + 1
          op(q, p, 1; op_params...)                        # q = A * p

          delta = (d_norm(q))^2 + shift * (m_norm(p))^2    # ||q||_2^2 + shift*||p||_2^2
          indefinite = delta <= 0.0 ? true  : false
          delta      = delta == 0.0 ? eps() : delta

          alpha = gamma / delta

          m_axpby(alpha, p, 1.0, x)                        # x = x + alpha * p
          d_axpby(-alpha, q, 1.0, r)                       # r = r - alpha * q

          data_fitting = (d_norm(r))^2                     # ||r||_2^2
          constraint   = shift * (m_norm(x))^2             # shift*||x||_2^2
          cost         = data_fitting + constraint         # ||r||_2^2 + shift*||x||_2^2

          # save the intermidiate result
          path_iter = join([dir_iterations "/iteration" "_" "$k" ".rsf"])
          cp(x, path_iter, force=true)

          op(s, r, 2; op_params...)
          m_axpby(-shift, x, 1.0, s)                       # s = A' * r - shift * x

          norms  = m_norm(s)                               # ||s||_2
          gamma0 = gamma                                   # ||s||_2^2 previous iteration
          gamma  = norms^2                                 # ||s||_2^2
          beta   = gamma / gamma0

          m_axpby(1.0, s, beta, p)                         # p = s + beta * p

          # check the stopping crietia
          normx = m_norm(x)
          xmax  = normx > xmax ? normx : xmax
          if norms <= norms0 * tol || normx * tol >= 1.0
             run_flag = false
          end

          # print information
          resNE = cost / cost0
          if print_flag
             @printf("%3.0f %20.10e %20.10e %20.10e %20.10e\n", k, data_fitting, constraint, normx, resNE);
          end
          push!(convergence, resNE);
    end

    return x, convergence
end
