﻿#include <stdio.h>
#include <stdlib.h>

#include "common.h"
#include "cuda_common.cuh"

#include "cuda.h"
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

// for initializing arrays
void initialize(int* input, const int array_size,
	INIT_PARAM PARAM, int x)
{
	if (PARAM == INIT_ONE)
	{
		for (int i = 0; i < array_size; i++)
		{
			input[i] = 1;
		}
	}
	else if (PARAM == INIT_ONE_TO_TEN)
	{
		for (int i = 0; i < array_size; i++)
		{
			input[i] = i % 10;
		}
	}
	else if (PARAM == INIT_RANDOM)
	{
		time_t t;
		srand((unsigned)time(&t));
		for (int i = 0; i < array_size; i++)
		{
			input[i] = (int)(rand() & 0xFF);
		}
	}
	else if (PARAM == INIT_FOR_SPARSE_METRICS)
	{
		srand(time(NULL));
		int value;
		for (int i = 0; i < array_size; i++)
		{
			value = rand() % 25;
			if (value < 5)
			{
				input[i] = value;
			}
			else
			{
				input[i] = 0;
			}
		}
	}
	else if (PARAM == INIT_0_TO_X)
	{
		srand(time(NULL));
		int value;
		for (int i = 0; i < array_size; i++)
		{
			input[i] = (int)(rand() & 0xFF);
		}
	}
}

int reduction_cpu(int* input, const int size)
{
	int sum = 0;
	for (int i = 0; i < size; i++)
	{
		sum += input[i];
	}
	return sum;
}

void compare_results(int gpu_result, int cpu_result)
{
	printf("GPU result : %d , CPU result : %d \n",
		gpu_result, cpu_result);

	if (gpu_result == cpu_result)
	{
		printf("GPU and CPU results are same \n");
		return;
	}

	printf("GPU and CPU results are different \n");
}

__global__ void reduction_kernel_complete_unrolling(int* int_array,
	int* temp_array, int size)
{
	int tid = threadIdx.x;

	//element index for this thread
	int index = blockDim.x * blockIdx.x + threadIdx.x;

	//local data pointer
	int* i_data = int_array + blockDim.x * blockIdx.x;

	if (blockDim.x >= 1024 && tid < 512)
		i_data[tid] += i_data[tid + 512];
	__syncthreads();

	if (blockDim.x >= 512 && tid < 256)
		i_data[tid] += i_data[tid + 256];
	__syncthreads();

	if (blockDim.x >= 256 && tid < 128)
		i_data[tid] += i_data[tid + 128];
	__syncthreads();

	if (blockDim.x >= 128 && tid < 64)
		i_data[tid] += i_data[tid + 64];
	__syncthreads();

	if (tid < 32)
	{
		volatile int* vsmem = i_data;
		vsmem[tid] += vsmem[tid + 32];
		vsmem[tid] += vsmem[tid + 16];
		vsmem[tid] += vsmem[tid + 8];
		vsmem[tid] += vsmem[tid + 4];
		vsmem[tid] += vsmem[tid + 2];
		vsmem[tid] += vsmem[tid + 1];
	}

	if (tid == 0)
	{
		temp_array[blockIdx.x] = i_data[0];
	}
}


int main(int argc, char ** argv)
{
	printf("Running parallel reduction with neighbored pairs improved kernel \n");

	int size = 1 << 27;
	int byte_size = size * sizeof(int);
	int block_size = 128;

	int * h_input, *h_ref;
	h_input = (int*)malloc(byte_size);

 	initialize(h_input, size, INIT_RANDOM);

	int cpu_result = reduction_cpu(h_input, size);

	dim3 block(block_size);
	dim3 grid(size / block.x);

	printf("Kernel launch parameters || grid : %d, block : %d \n", grid.x, block.x);

	int temp_array_byte_size = sizeof(int)* grid.x;

	h_ref = (int*)malloc(temp_array_byte_size);

	int * d_input, *d_temp;
	gpuErrchk(cudaMalloc((void**)&d_input, byte_size));
	gpuErrchk(cudaMalloc((void**)&d_temp, temp_array_byte_size));

	gpuErrchk(cudaMemset(d_temp, 0, temp_array_byte_size));
	gpuErrchk(cudaMemcpy(d_input, h_input, byte_size,
		cudaMemcpyHostToDevice));

	reduction_kernel_complete_unrolling  << < grid, block >> > (d_input, d_temp, size);

	gpuErrchk(cudaDeviceSynchronize());
	gpuErrchk(cudaMemcpy(h_ref, d_temp, temp_array_byte_size, cudaMemcpyDeviceToHost));

	int gpu_result = 0;
	for (int i = 0; i < grid.x; i++)
	{
		gpu_result += h_ref[i];
	}

	compare_results(gpu_result, cpu_result);

	gpuErrchk(cudaFree(d_input));
	gpuErrchk(cudaFree(d_temp));
	free(h_input);
	free(h_ref);

	gpuErrchk(cudaDeviceReset());
	return 0;
}