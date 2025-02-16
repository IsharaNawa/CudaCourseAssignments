﻿#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "cuda.h"
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "cuda_common.cuh"

// compile this code using "nvcc kernel.cu -o kernel"
// ignore the warnings
// profile the program using "nvprof --metrics branch_efficiency kernel"
// output should be 100% branch efficiency , because compiler will add optimizations for conditions
// if we disable optimizations , using "nvcc -G kernel.cu -o kernel", then compiler will not optimize it
// then run the profiler. Now divergence have 83.33% branch efficiency. Becuase in nvprof, it will consider the
// rest of the code lines in the kernal into consideration when calculating the branch efficiency.

__global__ void code_without_divergence()
{
	int gid = blockIdx.x * blockDim.x + threadIdx.x;

	float a, b;
	a = b = 0;

	int warp_id = gid / 32;

	if (warp_id % 2 == 0)
	{
		a = 100.0;
		b = 50.0;
	}
	else
	{
		a = 200;
		b = 75;
	}
}

__global__ void divergence_code()
{
	int gid = blockIdx.x * blockDim.x + threadIdx.x;

	float a, b;
	a = b = 0;

	if (gid % 2 == 0)
	{
		a = 100.0;
		b = 50.0;
	}
	else
	{
		a = 200;
		b = 75;
	}
}

int main(int argc, char** argv)
{
	printf("\n-----------------------WARP DIVERGENCE EXAMPLE------------------------ \n\n");

	int size = 1 << 22;

	dim3 block_size(128);
	dim3 grid_size((size + block_size.x -1)/ block_size.x);

	code_without_divergence << <grid_size, block_size >> > ();
	cudaDeviceSynchronize();

	divergence_code << <grid_size, block_size >> > ();
	cudaDeviceSynchronize();

	cudaDeviceReset();
	return 0;
}