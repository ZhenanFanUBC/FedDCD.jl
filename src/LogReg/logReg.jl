using LinearAlgebra
using SparseArrays

# Calculate the objective of logistic regression:
# \frac{1}{n} \sum_{i=1}^n \log( 1 + \exp( -w^T x_i y_i ) ) + \lambda/2 \|w\|^2.
function obj(
    X::SparseMatrixCSC{Float64, Int64},
    y::Vector{Int64},
    W::Matrix{Float64},
    λ::Float64
)
    n, _ = size(X)
    XW = X*W
    objval = 0.0
    for i = 1:n
        prob = softmax(XW[i,:])
        objval += -log(prob[ y[i] ])
    end
    objval /= n
    objval += λ/2*norm(W)^2
    return objval
end

# Calculate the objective of neural network model:
function obj(
    Xt::SparseMatrixCSC{Float64, Int64},
    Y::Flux.OneHotArray,
    W::Flux.Chain,
    λ::Float64
)
    loss(x,y) = Flux.Losses.crossentropy(W(x), y)
    l = 0.0
    num_data = size(Xt, 2)
    for i = 1:num_data
        l += loss(Xt[:,i], Y[:,i])
    end
    sqnorm(w) = sum(abs2, w)
    return l/num_data + (λ/2) * sum(sqnorm, params(W))
end

# Line-search for softmax
function lineSearch(
    X::SparseMatrixCSC{Float64, Int64},
    y::Vector{Int64},
    D::Matrix{Float64},
    W::Matrix{Float64},
    G::Matrix{Float64},
    λ::Float64
)
    maxLineSearchSteps = 100
    GTD = dot(G, D)
    # @show(GTD)
    Wnorm = norm(W)
    XW = X*W
    XD = X*D
    
    n = size(X, 1)
    objval = 0.0
    @inbounds for i = 1:n
        prob = softmax(XW[i,:])
        objval += -log(prob[ y[i] ])
    end
    objval /= n
    objval += λ/2*Wnorm^2
    
    Wnew = zeros(Float64, size(W))
    XWnew = zeros(Float64, size(XW))

    η = 1.0
    β = 1e-2
    for t = 1:maxLineSearchSteps
        Wnew .= W - η*D
        XWnew .= XW - η*XD
        objNew = 0.0
        @inbounds for i = 1:n
            prob = softmax(XWnew[i,:])
            objNew += -log(prob[ y[i] ])
        end
        objNew /= n
        objNew += λ/2*norm(Wnew)^2
        if objNew > objval - β*η*GTD
            η *= 0.5
        else
            break
        end
        if t == maxLineSearchSteps
            @warn("Reached maximum linesearch steps.")
        end
    end
    return η
end

# Line-search for FedDCD
function lineSearch2(
    X::SparseMatrixCSC{Float64, Int64},
    Y::Vector{Int64},
    y::Matrix{Float64},  # dual variable
    D::Matrix{Float64},
    W::Matrix{Float64},
    G::Matrix{Float64},
    λ::Float64
)
    maxLineSearchSteps = 100
    GTD = dot(G, D)
    # @show(GTD)
    Wnorm = norm(W)
    XW = X*W
    XD = X*D
    WTy = dot(W, y)
    DTy = dot(D, y)
    
    n = size(X, 1)
    objval = 0.0
    @inbounds for i = 1:n
        prob = softmax(XW[i,:])
        objval += -log(prob[ Y[i] ])
    end
    objval /= n
    objval -= WTy   # objective have an additional term -W^Ty
    objval += λ/2*Wnorm^2
    
    Wnew = zeros(Float64, size(W))
    XWnew = zeros(Float64, size(XW))

    η = 1.0
    β = 1e-2
    for t = 1:maxLineSearchSteps
        Wnew .= W - η*D
        XWnew .= XW - η*XD
        objNew = 0.0
        @inbounds for i = 1:n
            prob = softmax(XWnew[i,:])
            objNew += -log(prob[ Y[i] ])
        end
        objNew /= n
        objNew -= ( WTy - η*DTy )
        objNew += λ/2*norm(Wnew)^2
        if objNew > objval - β*η*GTD
            η *= 0.5
        else
            break
        end
        if t == maxLineSearchSteps
            @warn("Reached maximum linesearch steps.")
        end
    end
    return η
end


# Calculate the accuracy
function accuracy(
    X::SparseMatrixCSC{Float64, Int64},
    y::Vector{Int64},
    W::Matrix{Float64},
)
    n = size(X, 1)
    XW = X*W
    ret = 0
    for i = 1:n
        prob = softmax( XW[i,:] )
        if argmax(prob) == y[i]
            ret += 1
        end
    end
    return ret/n
end

# Calculate the accuracy
function accuracy(
    X::SparseMatrixCSC{Float64, Int64},
    Y::Flux.OneHotArray,
    W::Flux.Chain,
)
    Xt = copy(X')
    acc(x,y) = 1.0* ( Flux.onecold(W(x)) == Flux.onecold(y) )
    num_data = size(Xt, 2)
    out = 0.0
    for i = 1:num_data
        out += acc(Xt[:,i], Y[:,i])
    end
    return out/num_data
end


# Calculate the stochastic gradient
function getStochasticGrad(
    Xt::SparseMatrixCSC{Float64, Int64},
    y::Vector{Int64},
    W::Matrix{Float64},
    idx::Int64
)
    x = Xt[:,idx]
    Wtx = W'*x
    s = softmax( Wtx )
    s[ y[idx] ] -= 1
    g = x * s'
    return g
end


# Calculate gradient
function getGradient(
    X::SparseMatrixCSC{Float64, Int64},
    Xt::SparseMatrixCSC{Float64, Int64},
    y::Vector{Int64},
    W::Matrix{Float64},
    λ::Float64
)
    n, d = size(X)
    _, K = size(W)
    g = zeros(Float64, d, K)
    XW = X*W
    @inbounds for i = 1:n
        s = softmax( XW[i,:] )
        s[ y[i] ] -= 1
        x = Xt[:,i]
        I, V = findnz(x)
        @inbounds for col = 1:K
            @inbounds for j = 1:length(I)
                row = I[j]
                val = V[j]
                g[row, col] += val*s[col]
            end
        end
    end
    g ./= n
    g += λ.*W
    return g
end

# Add a dense matrix with a sparse matrix in place, A = A + x * b', x sparse, b dense.
function FastHvMatrixUpdate!(
    A::Matrix{Float64},
    x::SparseVector{Float64,Int64},
    b::Vector{Float64}
)
    I, V = findnz(x)
    K = length(b)
    @inbounds for col = 1:K 
        @inbounds for idx = 1:length(I)
            row = I[idx]
            v = V[idx]
            A[row, col] += v*b[col]
        end
    end
    return nothing
end

# Fast Hessian-vector product for softmax classification
function FastHv(
    X::SparseMatrixCSC{Float64, Int64},
    Xt::SparseMatrixCSC{Float64, Int64},
    W::Matrix{Float64},
    λ::Float64,
    V::Matrix{Float64}
)
    # Time complexity is O( nnz(X)*K )
    n, d = size(X)
    _, K = size(W)
    XW = X*W
    XV = X*V
    P = zeros(Float64, n, K)
    ret = zeros(Float64, d, K)
    for i = 1:n
        P[i,:] = softmax( XW[i,:] )
    end
    @inbounds for i = 1:n 
        # Complexity of the loop: nnz(xi)*K
        # Calculate (x_i x_i^T V ( Λ - p_i p_i^T ) )
        xi = Xt[:, i]
        ppi = P[i, :]
        # First calculate x_i^T V
        xtV = XV[i, :]
        # # Calculate x_i^T V ( Λ - p_i p_i^T )
        xtVppt = xtV .* ppi
        xtVppt -= dot(xtV, ppi) .* ppi
        # # Calculate x_i x_i^T V ( Λ - p_i p_i^T )
        FastHvMatrixUpdate!( ret, xi, xtVppt)
        # ret += xi*xtVppt'
    end
    ret ./= n
    ret += λ.*V
    return ret
end


# Compute Newton direction. Use cg to solve the linear system H D = g.
function ComputeNewtonDirection(
    X::SparseMatrixCSC{Float64, Int64},
    Xt::SparseMatrixCSC{Float64, Int64},
    W::Matrix{Float64},
    λ::Float64,
    g::Matrix{Float64}
)
    n, d = size(X)
    _, K = size(W)
    
    H = LinearMap(v->vec(FastHv(X, Xt, W, λ, reshape(v,d,K))), d*K, issymmetric=true, isposdef=true)
    D = cg(H, vec(g), abstol=1e-8, reltol=1e-4, maxiter=1000)

    return reshape(D, d, K)
end


# Using Newton's method to solve the softmax classification problem.
function SoftmaxNewtonMethod(
    X::SparseMatrixCSC{Float64, Int64},
    Xt::SparseMatrixCSC{Float64, Int64},
    y::Vector{Int64},
    W::Matrix{Float64},
    λ::Float64,
    maxIter::Int64=20,
    tol::Float64=1e-4
)
    startTime = time()
    for iter = 1:maxIter
        objval = obj(X, y, W, λ)
        g = getGradient(X, Xt, y, W, λ)
        gnorm = norm(g)
        @printf("Iter %3d, obj: %4.5e, gnorm: %4.5e, time: %4.2f\n", iter, objval, gnorm, time()-startTime)
        if gnorm < tol
            break
        end
        # Compute Newton direction.
        D = ComputeNewtonDirection( X, Xt, W, λ, g)
        η = lineSearch(X, Y, D, W, g, λ)
        W .-= η*D
    end
    return W
end