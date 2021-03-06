########################################################################
# Client
########################################################################\

using LinearAlgebra
using SparseArrays
using Random
using Printf

# Abstract class for client
abstract type AbstractClient end

# Client upload model to server
function update! end

# # Client download model to server
# function download end

include("fedProxClient.jl")
include("ScaffoldClient.jl")
include("fedDCDClient.jl")




