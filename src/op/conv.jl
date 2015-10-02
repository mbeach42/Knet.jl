import Base: conv
using CUDNN: cudnnConvolutionDescriptor_t

type Conv <: Op; padding; stride; upscale; mode; end

ninputs(::Conv)=2
overwrites(::Conv)=false
back_reads_x(::Conv)=true
back_reads_y(::Conv)=false

function conv(; padding=0, stride=1, upscale=1, mode=CUDNN_CONVOLUTION)
    @assert in(mode, (CUDNN_CONVOLUTION, CUDNN_CROSS_CORRELATION))
    Conv(padding, stride, upscale, mode)
end

function forw(c::Conv, w, x, y; o...)
    if w == nothing
        error("Uninitialized filter")
    elseif x == nothing
        return nothing
    end
    cudnnConvolutionForward_v4(x, w, y; padding=c.padding, stride=c.stride, upscale=c.upscale, mode=c.mode)
end

function back(c::Conv, dy, dw, dx; x=nothing, o...)
    dw == nothing && dx == nothing && return
    dw != nothing && (x[2] != nothing ? cudnnConvolutionBackwardFilter_v4(x[2], dy, dw; padding=c.padding, stride=c.stride, upscale=c.upscale, mode=c.mode) : fill!(dw,0))
    dx != nothing && (x[1] != nothing ? cudnnConvolutionBackwardData_v4(x[1], dy, dx; padding=c.padding, stride=c.stride, upscale=c.upscale, mode=c.mode) : error("Uninitialized filter"))
end

# x: (x1,x2...,C,N)
# w: (w1,w2...,C,K)
# y: (y1,y2...,K,N)
# Assuming padding=0 and stride=1: yi=xi-wi+1
# In general we have: yi = 1 + (xi + 2*padding - wi) / stride

function infersize(::Conv,w,x)
    @assert length(w) == length(x)
    nd = length(x)
    x = [x...]
    w = [w...]
    x[nd-1] == 0 && (x[nd-1] = w[nd-1])
    w[nd-1] == 0 && (w[nd-1] = x[nd-1])
    @assert x[nd-1] == w[nd-1]
    y = zeros(x)
    for i=1:nd-2
        w[i] > 0 && x[i] > 0 && (y[i] = x[i]-w[i]+1)
    end
    y[nd-1] = w[nd]
    y[nd] = x[nd]
    return (tuple(w...), tuple(x...), tuple(y...))
end

### DEAD CODE

# TODO: generalize to N-D
# TODO: cpu implementation
# TODO: upgrade to new cudnn version
# TODO: upgrade to new knet interface

# type Conv <: Op; w; x; ybuf; dx; Conv(p::KUparam)=new(p); end

# Conv(d...; o...)=Conv(KUparam(d...; o...))
# Conv(nout::Integer, width::Integer; o...)=Conv(KUparam(width, 0, nout; o...))

# params(l::Conv)=Any[l.w]
# ninputs(::Conv)=1
# overwrites(::Conv)=false
# back_reads_x(::Conv)=true
# back_reads_y(::Conv)=false

# # TODO: this unnecessarily allocates w and y
# ysize(l::Conv, x)=(isempty(l.w) && initforw(l,x,nothing); cudnnGetConvolutionNdForwardOutputDim(x,l.w))

# function forw(l::Conv, x; y=nothing, o...)
#     l.x = x
#     y = initforw(l,x,y)
#     cudnnConvolutionForward(x, l.w, y)
# end

# function back(l::Conv, dy; dx=nothing, x=l.x, incr=false, returndx=true, o...)
#     initback(l, dy, x, incr)
#     if incr
#         cudnnConvolutionBackwardFilter(x, dy, l.w.inc)
#         axpy!(1, l.w.inc, l.w.diff)
#     else
#         cudnnConvolutionBackwardFilter(x, dy, l.w.diff)
#     end
#     if returndx
#         dx = initbackx(l,x,dx)
#         cudnnConvolutionBackwardData(l.w, dy, dx)
#     end
# end

# function initback(l::Conv, dy, x, incr)
#     atype(dy) == atype(x) || error("atype mismatch")
#     eltype(dy) == eltype(x) || error("eltype mismatch")
#     size(dy) == ysize(l,x) || error("ysize mismatch")
#     similar!(l.w, :diff, l.w.arr)
#     incr && similar!(l.w, :inc, l.w.arr)
# end

# function initbackx(l::Conv, x, dx)
#     dx == nothing && (dx = similar!(l, :dx, x))
#     issimilar(dx,x) || error("Gradient mismatch")
#     return dx
# end

# # TODO: We should split up the w and y parts and share with Mmul

# function initforw(l::Conv, x, y)
#     n = ndims(x)
#     c = size(x)[n-1]  # x dims are (x1, x2, ..., channels, images)
#     if isempty(l.w) 
#         nz(l.w,:init,nothing) || (l.w.init = xavier!)
#         r = size(l.w, 1)
#         o = size(l.w, ndims(l.w))
#         wsize = ntuple(i->(i<n-1 ? r : i==n-1 ? c : o), n)
#         init(l.w, eltype(x), wsize)
#     end
#     eltype(x) == eltype(l.w) || "$(eltype(x)) != $(eltype(l.w))"
#     n == ndims(l.w) || error("ndims mismatch")
#     c == size(l.w)[n-1] || error("channel mismatch")
#     ys = ysize(l,x)
#     y == nothing && (y = similar!(l, :ybuf, x, ys))
#     typeof(y) == typeof(x) || error("Type mismatch")
#     size(y) == ys || error("Size mismatch")
#     return y
# end

# xavier!(a)=(fanin = length(a) / (size(a)[end]); scale = sqrt(3 / fanin); rand!(a, -scale, scale); a)

# # Make things work with KUdense

# import CUDNN: cudnnGetConvolutionNdForwardOutputDim, cudnnConvolutionForward, cudnnConvolutionBackwardFilter, cudnnConvolutionBackwardData

# cudnnGetConvolutionNdForwardOutputDim(x::KUdense, w::KUparam)=cudnnGetConvolutionNdForwardOutputDim(x.arr, w.arr)
# cudnnConvolutionForward(x::KUdense, w::KUparam, y::KUdense)=(cudnnConvolutionForward(x.arr, w.arr, y.arr);y)
# cudnnConvolutionBackwardFilter(x::KUdense, dy::KUdense, w::BaseArray)=(cudnnConvolutionBackwardFilter(x.arr, dy.arr, w);w)
# cudnnConvolutionBackwardData(w::KUparam, dy::KUdense, dx::KUdense)=(cudnnConvolutionBackwardData(w.arr, dy.arr, dx.arr);dx)

# Make things work with CPU (for now)

# cudnnGetConvolutionNdForwardOutputDim(x::Array, w::Array)=cudnnGetConvolutionNdForwardOutputDim(CudaArray(x),CudaArray(w))
# cudnnConvolutionForward(x::Array, w::Array, y::Array)=(y1=CudaArray(y);cudnnConvolutionForward(CudaArray(x), CudaArray(w), y1);copy!(y,1,y1,1,length(y)))
# cudnnConvolutionBackwardFilter(x::Array, dy::Array, w::Array)=(w1=CudaArray(w);cudnnConvolutionBackwardFilter(CudaArray(x), CudaArray(dy), w1); copy!(w,1,w1,1,length(w)))
# cudnnConvolutionBackwardData(w::Array, dy::Array, dx::Array)=(dx1=CudaArray(dx);cudnnConvolutionBackwardData(CudaArray(w), CudaArray(dy), dx1); copy!(dx,1,dx1,1,length(dx)))
