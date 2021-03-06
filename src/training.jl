########################################################################
# Training
########################################################################

# Implementation of the FedAvg and FedProx algorithm
function fedAvgAndProx(
    server::Union{FedProxServer, FedProxServerNN},
    clients::Union{Vector{FedProxClient}, Vector{FedProxClientNN} },
    numRounds::Int64
)
    # Connect clients with server
    server.clients = clients
    # Training process
    objList = zeros(Float64, 0)
    testAccList = zeros(Float64, 0)
    startTime = time()
    @printf("Start training!\n")
    for t = 1:numRounds
        select!(server)
        sendModel!(server)
        # objValue = getObjValue(server)
        # @printf("Round : %4d, obj: %6.4e\n", t, objValue)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            update!(client)
        end
        @printf("aggregate\n")
        aggregate!(server)
        # Print log
        sendModelToAllClients!(server)
        @printf("getObj\n")
        objValue = getObjValue(server)
        acc = accuracy(server.Xtest, server.Ytest, server.W)
        @printf("Round : %4d, obj: %6.4e, acc: % 3.2f %%, time: %4.3f s\n", t, objValue, acc*100, time()-startTime)
        push!(objList, objValue)
        push!(testAccList, acc)
        if isnan(objValue)
            break
        end
    end
    endTime = time()
    @printf("Finished training, time elapsed: %.4e\n", endTime - startTime)
    return server.W, objList, testAccList
end

# Implementation of the Scaffold algorithm.
function Scaffold(
    server::Union{ScaffoldServer, ScaffoldServerNN},
    clients::Union{Vector{ScaffoldClient}, Vector{ScaffoldClientNN} },
    numRounds::Int64
)
    # Connect clients with server
    server.clients = clients
    # Training process
    objList = zeros(Float64, 0)
    testAccList = zeros(Float64, 0)
    startTime = time()
    @printf("Start training!\n")
    for t = 1:numRounds
        select!(server)
        sendModel!(server)
        # objValue = getObjValue(server)
        # @printf("Round : %4d, obj: %6.4e\n", t, objValue)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            update!(client)
        end
        aggregate!(server)
        # Print log
        sendModelToAllClients!(server)
        objValue = getObjValue(server)
        acc = accuracy(server.Xtest, server.Ytest, server.W)
        @printf("Round : %4d, obj: %6.4e, acc: % 3.2f %%, time: %4.3f s\n", t, objValue, acc*100, time()-startTime)
        push!(objList, objValue)
        push!(testAccList, acc)
        if isnan(objValue)
            break
        end
    end
    endTime = time()
    @printf("Finished training, time elapsed: %.4e\n", endTime - startTime)
    return server.W, objList, testAccList
end

# Implementation of the FedDCD algorithm (both exact and inexact)
function fedDCD(
    server::FedDCDServer,
    clients::Vector{FedDCDClient},
    numRounds::Int64
)
    # Connect clients with server
    server.clients = clients
    # Training process
    objList = zeros(Float64, 0)
    testAccList = zeros(Float64, 0)
    startTime = time()
    @printf("Start training!\n")
    for t = 1:numRounds
        # @printf("Round %d\n", t)
        select!(server)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            update!(client)
        end
        aggregate!(server)
        sendModel!(server)
        # Print log
        objValue = getObjValue(server)
        acc = accuracy(server.Xtest, server.Ytest, server.W)
        @printf("Round : %4d, obj: %6.4e, acc: % 3.2f %%, time: %4.3f s\n", t, objValue, acc*100, time()-startTime)
        push!(objList, objValue)
        push!(testAccList, acc)
        if isnan(objValue)
            break
        end
    end
    endTime = time()
    @printf("Finished training, time elapsed: %.4e\n", endTime - startTime)
    return server.W, objList, testAccList
end

function fedDCD(
    server::FedDCDServerNN,
    clients::Vector{FedDCDClientNN},
    numRounds::Int64
)
    # Connect clients with server
    server.clients = clients
    # Training process
    objList = zeros(Float64, 0)
    testAccList = zeros(Float64, 0)
    startTime = time()
    @printf("Start training!\n")
    for t = 1:numRounds
        # @printf("Round %d\n", t)
        select!(server)
        synchronize!(server)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            update!(client)
        end
        aggregate!(server)
        sendModel!(server)
        decay_lr!(server)
        # Print log
        objValue = getObjValue(server)
        # acc = 0.0
        # num_data = 0
        # for c in server.clients
        #     n = size(c.Xtrain, 1)
        #     num_data += n
        #     acc += n*accuracy(c.XtrainT, c.Ytrain, server.W)
        # end
        # acc /= num_data
        acc = accuracy(server.Xtest, server.Ytest, server.W)
        @printf("Round : %4d, obj: %6.4e, acc: % 3.2f %%, time: %4.3f s\n", t, objValue, acc*100, time()-startTime)
        push!(objList, objValue)
        push!(testAccList, acc)
        if isnan(objValue)
            break
        end
    end
    endTime = time()
    @printf("Finished training, time elapsed: %.4e\n", endTime - startTime)
    return server.W, objList, testAccList
end


# Implementation of the accelerated FedDCD algorithm
function accfedDCD(
    server::AccFedDCDServer,
    clients::Vector{AccFedDCDClient},
    numRounds::Int64;
    objMin::Float64 = 0.0
)
    # Connect clients with server
    server.clients = clients
    # Training process
    objList = zeros(Float64, 0)
    testAccList = zeros(Float64, 0)
    startTime = time()
    @printf("Start training!\n")
    for t = 1:numRounds
        # @printf("Round %d\n", t)
        # update v
        Threads.@threads for client in server.clients
            updatev!(client)
        end
        # first inner round
        select!(server)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            updateW!(client)
        end
        aggregate!(server)
        sendModel!(server, 1)
        # update u
        Threads.@threads for client in server.clients
            updateu!(client)
        end
        # second inner round
        select!(server)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            updateW!(client)
        end
        aggregate!(server)
        sendModel!(server, 2)
        # Print log
        objValue = getObjValue(server)
        acc = accuracy(server.Xtest, server.Ytest, server.W)
        @printf("Round : %4d, obj: %6.4e, acc: % 3.2f %%, time: %4.3f s\n", t, objValue, acc*100, time()-startTime)
        push!(objList, objValue)
        push!(testAccList, acc)
        if objValue < objMin
            break
        end
        if isnan(objValue)
            break
        end
    end
    endTime = time()
    @printf("Finished training, time elapsed: %.4e\n", endTime - startTime)
    return server.W, objList, testAccList
end


function accfedDCD(
    server::AccFedDCDServerNN,
    clients::Vector{AccFedDCDClientNN},
    numRounds::Int64;
    objMin::Float64 = 0.0
)
    # Connect clients with server
    server.clients = clients
    # Training process
    objList = zeros(Float64, 0)
    testAccList = zeros(Float64, 0)
    startTime = time()
    @printf("Start training!\n")
    for t = 1:numRounds
        # update v
        Threads.@threads for client in server.clients
            updatev!(client)
        end
        # first inner round
        select!(server)
        synchronize!(server)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            updateW!(client)
        end
        aggregate!(server)
        sendModel!(server, 1)
        # update u
        Threads.@threads for client in server.clients
            updateu!(client)
        end
        # second inner round
        select!(server)
        synchronize!(server)
        Threads.@threads for idx in server.selectedIndices
            client = server.clients[idx]
            updateW!(client)
        end
        aggregate!(server)
        sendModel!(server, 2)
        # Print log
        objValue = getObjValue(server)
        acc = accuracy(server.Xtest, server.Ytest, server.W)
        @printf("Round : %4d, obj: %6.4e, acc: % 3.2f %%, time: %4.3f s\n", t, objValue, acc*100, time()-startTime)
        push!(objList, objValue)
        push!(testAccList, acc)
        if objValue < objMin
            break
        end
        if isnan(objValue)
            break
        end
    end
    endTime = time()
    @printf("Finished training, time elapsed: %.4e\n", endTime - startTime)
    return server.W, objList, testAccList
end
