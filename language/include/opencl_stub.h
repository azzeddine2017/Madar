/*
**  Madar - High-Performance AI-Native Runtime
**  OpenCL Stub & Dynamic Loader Header
**  Zero-Copy GPU Acceleration for Unified Memory (Intel HD Graphics & Discrete GPUs)
*/

#ifndef MADAR_OPENCL_STUB_H
#define MADAR_OPENCL_STUB_H

#ifdef _WIN32
#include <windows.h>
#define CL_API_CALL __stdcall
#else
#define CL_API_CALL
#endif

#include <stddef.h>

typedef struct _cl_platform_id *    cl_platform_id;
typedef struct _cl_device_id *      cl_device_id;
typedef struct _cl_context *        cl_context;
typedef struct _cl_command_queue *  cl_command_queue;
typedef struct _cl_mem *            cl_mem;
typedef struct _cl_program *        cl_program;
typedef struct _cl_kernel *         cl_kernel;
typedef struct _cl_event *          cl_event;

typedef unsigned int                cl_uint;
typedef int                         cl_int;
typedef unsigned long long          cl_ulong;
typedef cl_ulong                    cl_bitfield;
typedef cl_bitfield                 cl_mem_flags;

#define CL_SUCCESS                                  0
#define CL_DEVICE_TYPE_DEFAULT                      (1 << 0)
#define CL_DEVICE_TYPE_CPU                          (1 << 1)
#define CL_DEVICE_TYPE_GPU                          (1 << 2)
#define CL_DEVICE_TYPE_ALL                          0xFFFFFFFF

#define CL_MEM_READ_WRITE                           (1 << 0)
#define CL_MEM_WRITE_ONLY                           (1 << 1)
#define CL_MEM_READ_ONLY                            (1 << 2)
#define CL_MEM_USE_HOST_PTR                         (1 << 3)
#define CL_MEM_ALLOC_HOST_PTR                       (1 << 4)
#define CL_MEM_COPY_HOST_PTR                        (1 << 5)

#define CL_DEVICE_NAME                              0x102B
#define CL_PROGRAM_BUILD_LOG                        0x1183
#define CL_TRUE                                     1
#define CL_FALSE                                    0

/* Dynamic Function Pointer Types */
typedef cl_int (CL_API_CALL *pfn_clGetPlatformIDs)(cl_uint, cl_platform_id *, cl_uint *);
typedef cl_int (CL_API_CALL *pfn_clGetDeviceIDs)(cl_platform_id, cl_bitfield, cl_uint, cl_device_id *, cl_uint *);
typedef cl_int (CL_API_CALL *pfn_clGetDeviceInfo)(cl_device_id, cl_uint, size_t, void *, size_t *);
typedef cl_context (CL_API_CALL *pfn_clCreateContext)(const void *, cl_uint, const cl_device_id *, void *, void *, cl_int *);
typedef cl_command_queue (CL_API_CALL *pfn_clCreateCommandQueue)(cl_context, cl_device_id, cl_bitfield, cl_int *);
typedef cl_mem (CL_API_CALL *pfn_clCreateBuffer)(cl_context, cl_mem_flags, size_t, void *, cl_int *);
typedef cl_program (CL_API_CALL *pfn_clCreateProgramWithSource)(cl_context, cl_uint, const char **, const size_t *, cl_int *);
typedef cl_int (CL_API_CALL *pfn_clBuildProgram)(cl_program, cl_uint, const cl_device_id *, const char *, void *, void *);
typedef cl_int (CL_API_CALL *pfn_clGetProgramBuildInfo)(cl_program, cl_device_id, cl_uint, size_t, void *, size_t *);
typedef cl_kernel (CL_API_CALL *pfn_clCreateKernel)(cl_program, const char *, cl_int *);
typedef cl_int (CL_API_CALL *pfn_clSetKernelArg)(cl_kernel, cl_uint, size_t, const void *);
typedef cl_int (CL_API_CALL *pfn_clEnqueueNDRangeKernel)(cl_command_queue, cl_kernel, cl_uint, const size_t *, const size_t *, const size_t *, cl_uint, const cl_event *, cl_event *);
typedef cl_int (CL_API_CALL *pfn_clEnqueueReadBuffer)(cl_command_queue, cl_mem, cl_uint, size_t, size_t, void *, cl_uint, const cl_event *, cl_event *);
typedef cl_int (CL_API_CALL *pfn_clEnqueueWriteBuffer)(cl_command_queue, cl_mem, cl_uint, size_t, size_t, const void *, cl_uint, const cl_event *, cl_event *);
typedef cl_int (CL_API_CALL *pfn_clFinish)(cl_command_queue);
typedef cl_int (CL_API_CALL *pfn_clReleaseMemObject)(cl_mem);
typedef cl_int (CL_API_CALL *pfn_clReleaseKernel)(cl_kernel);
typedef cl_int (CL_API_CALL *pfn_clReleaseProgram)(cl_program);
typedef cl_int (CL_API_CALL *pfn_clReleaseCommandQueue)(cl_command_queue);
typedef cl_int (CL_API_CALL *pfn_clReleaseContext)(cl_context);

#endif /* MADAR_OPENCL_STUB_H */
