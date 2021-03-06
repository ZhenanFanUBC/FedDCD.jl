########################################################################
# Helper Functions
########################################################################

# Write results to CSV.
function writeToFile(
    dataName::String,
    modelName::String,
    serverConfig::Dict,
    clientConfig::Dict,
    objList::Vector{Float64},
    testAccList::Vector{Float64},
    filename::String
)
    f = open(filename, "w")
    println(f, "# Configuration:\n")
    println(f, "dataset name: "*dataName)
    println(f, "model name: "*modelName)
    for (key, value) in serverConfig
        println(f, string(key)*": "*string(value))
    end
    for (key, value) in clientConfig
        println(f, string(key)*": "*string(value))
    end
    println(f, "# Results:\n")
    println(f, "round,obj,test")
    T = length(objList)
    for t = 1:T
        line = string(t)*","*string(objList[t])*","*string(testAccList[t])
        println(f, line )
    end
    close(f)
    return nothing
end

# softmax function
function softmax(z::Vector{Float64})
    expz = exp.(z)
    s = sum(expz)
    return expz ./ s
end

# negative log-likelihood function
function neg_log_loss(z::Vector{Float64}, y::Int64)
    return -log(z[y])
end

# Label transformation
function labelTransform(
    y::Vector{Int64},
    yTest::Vector{Int64}
    )
    d = Dict{Int64, Int64}()
    uniqueLabels = union( Set(y), Set(yTest) )
    cc = 1
    for label in uniqueLabels
        if !haskey(d, label)
            d[label] = cc
            cc += 1
        end
    end
    y = [ d[x] for x in y ]
    yTest = [ d[x] for x in yTest ]
    return y, yTest
end

# horizontally split data
function split_data(Xtrain::SparseMatrixCSC{Float64, Int64}, Ytrain::Vector{Int64}, num_clients::Int64)
    num_data = size(Xtrain, 2)
    num_data_client = div(num_data, num_clients)
    Xtrain_split = Vector{ SparseMatrixCSC{Float64, Int64} }(undef, num_clients)
    Ytrain_split = Vector{ Vector{Int64} }(undef, num_clients)
    t = 1
    for i = 1:num_clients
        if i < num_clients
            ids = collect(t: t+num_data_client-1)
        else
            ids = collect(t: num_data)
        end
        Xtrain_split[i] = Xtrain[:, ids]
        Ytrain_split[i] = Ytrain[ids]
        t += num_features_client
    end
    return Xtrain_split, Ytrain_split
end

# Split data by rows
function splitDataByRow(Xtrain::SparseMatrixCSC{Float64, Int64}, Ytrain::Vector{Int64}, num_clients::Int64)
    num_data, d = size(Xtrain)
    num_data_client = div(num_data, num_clients)
    XT = copy(Xtrain')
    Xtrain_split = Vector{ SparseMatrixCSC{Float64, Int64} }(undef, num_clients)
    Ytrain_split = Vector{ Vector{Int64} }(undef, num_clients)
    t = 1
    for i = 1:num_clients
        if i < num_clients
            ids = collect(t: t+num_data_client-1)
        else
            ids = collect(t: num_data)
        end
        # Xtrain_split[i] = Xtrain[:, ids]
        Xtrain_split[i] = copy( XT[:,ids]' )
        Ytrain_split[i] = Ytrain[ids]
        t += num_data_client
    end
    return Xtrain_split, Ytrain_split
end

# Split data by class
function splitDataByClass(Xtrain::SparseMatrixCSC{Float64, Int64}, Ytrain::Vector{Int64}, num_clients::Int64, num_classes::Int64)
    Random.seed!(1234)
    XT = copy(Xtrain')
    Xtrain_split = Vector{ SparseMatrixCSC{Float64, Int64} }(undef, num_clients)
    Ytrain_split = Vector{ Vector{Int64} }(undef, num_clients)
    # assign 2 classes to each client 
    classes_clients = Vector{Tuple{Int64, Int64}}(undef, num_clients)
    for i in 1:num_clients
        a = samplepair(collect(1:num_classes))
        classes_clients[i] = a
    end
    # clients in each class
    clients_in_classes = [ [] for _ = 1:num_classes]
    for i = 1:num_classes
        for j = 1:num_clients
            if (classes_clients[j][1] == i) || (classes_clients[j][2] == i)
                push!(clients_in_classes[i], j)
            end
        end
    end
    # intialize indices
    indices = [ [] for _ = 1:num_clients]
    for i = 1:length(Ytrain)
        class = Ytrain[i]
        j = rand(clients_in_classes[class])
        push!(indices[j], i)
    end
    # fill in
    for i in 1:num_clients
        ids = indices[i]
        Xtrain_split[i] = copy( XT[:,ids]' )
        Ytrain_split[i] = Ytrain[ids]
    end
    return Xtrain_split, Ytrain_split
end

# read data from libsvm
function read_libsvm(filename::String)
    numLine = 0
    nnz = 0
    open(filename, "r") do f
        while !eof(f)
            line = readline(f)
            info = split(line, " ")
            numLine += 1
            nnz += ( length(info)-1 )
            if line[end] == ' '
                nnz -= 1
            end
        end
    end
    @printf("number of lines: %i\n", numLine)
    n = numLine
    m = 0
    I = zeros(Int64, nnz)
    J = zeros(Int64, nnz)
    V = zeros(Float64, nnz)
    y = zeros(Int64, n)
    numLine = 0
    cc = 1
    open(filename, "r") do f
        while !eof(f)
            numLine += 1
            line = readline(f)
            info = split(line, " ")
            value = parse(Int64, info[1] )
            if value < 0
                value = Int64(2)
            end
            y[numLine] = value
            ll = length(info)
            if line[end] == ' '
                ll -= 1
            end
            for i = 2:ll
                idx, value = split(info[i], ":")
                idx = parse(Int, idx)
                value = parse(Float64, value)
                I[cc] = numLine
                J[cc] = idx
                V[cc] = value
                cc += 1
                m = max(m, idx)
            end
        end
    end
    return sparse(I, J, V, n, m), y
    #return sparse( J, I, V, m, n ), y
end
