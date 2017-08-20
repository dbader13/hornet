/**
 * @internal
 * @author Federico Busato                                                  <br>
 *         Univerity of Verona, Dept. of Computer Science                   <br>
 *         federico.busato@univr.it
 * @date August, 2017
 * @version v2
 *
 * @copyright Copyright © 2017 cuStinger. All rights reserved.
 *
 * @license{<blockquote>
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * * Neither the name of the copyright holder nor the names of its
 *   contributors may be used to endorse or promote products derived from
 *   this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 * </blockquote>}
 *
 * @file
 */
#include "Device/CubWrapper.cuh"
#include "Device/SafeCudaAPI.cuh"
#include "Device/VectorUtil.cuh"
#include "Host/Numeric.hpp"
#include <cub.cuh>

namespace xlib {

CubWrapper::CubWrapper(size_t num_items) noexcept : _num_items(num_items) {}

CubWrapper::~CubWrapper() noexcept {
    cuFree(_d_temp_storage);
}

//==============================================================================
//==============================================================================

template<typename T>
CubSortByValue<T>::CubSortByValue(const T* d_in, size_t num_items,
                                  T* d_sorted, T d_in_max) noexcept :
                                        CubWrapper(num_items),
                                        _d_in(d_in), _d_sorted(d_sorted),
                                        _d_in_max(d_in_max) {
    cub::DeviceRadixSort::SortKeys(_d_temp_storage, _temp_storage_bytes,
                                   _d_in, _d_sorted,
                                   _num_items, 0, xlib::ceil_log2(_d_in_max));
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
void CubSortByValue<T>::run() noexcept {
    cub::DeviceRadixSort::SortKeys(_d_temp_storage, _temp_storage_bytes,
                                   _d_in, _d_sorted,
                                   _num_items, 0, xlib::ceil_log2(_d_in_max));
}
//------------------------------------------------------------------------------

template<typename T, typename R>
CubSortByKey<T, R>::CubSortByKey(const T* d_key, const R* d_data_in,
                                 size_t num_items, T* d_key_sorted,
                                 R* d_data_out, T d_key_max) noexcept :
                        CubWrapper(num_items),
                        _d_key(d_key), _d_data_in(d_data_in),
                        _d_key_sorted(d_key_sorted),
                        _d_data_out(d_data_out),
                        _d_key_max(d_key_max) {

    const int num_bits = std::is_floating_point<T>::value ? sizeof(T) * 8 :
                         xlib::ceil_log2(_d_key_max);
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_key, _d_key_sorted,
                                    _d_data_in, _d_data_out,
                                    _num_items, 0, num_bits);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T, typename R>
void CubSortByKey<T, R>::run() noexcept {
    const int num_bits = std::is_floating_point<T>::value ? sizeof(T) * 8 :
                         xlib::ceil_log2(_d_key_max);
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_key, _d_key_sorted,
                                    _d_data_in, _d_data_out,
                                    _num_items, 0, num_bits);
}
//------------------------------------------------------------------------------

template<typename T, typename R>
CubSortPairs2<T, R>::CubSortPairs2(T* d_in1, R* d_in2, size_t num_items,
                                   T d_in1_max, R d_in2_max) :
                           CubWrapper(num_items), _d_in1(d_in1), _d_in2(d_in2),
                           _d_in1_max(d_in1_max), _d_in2_max(d_in2_max),
                           _internal_alloc(true) {

    cuMalloc(_d_in1_tmp, _num_items);
    cuMalloc(_d_in2_tmp, _num_items);
    auto max = std::max(_d_in1_max, d_in2_max);
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_in2, _d_in2_tmp, _d_in1, _d_in1_tmp,
                                    _num_items, 0, xlib::ceil_log2(max));
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T, typename R>
CubSortPairs2<T, R>::CubSortPairs2(T* d_in1, R* d_in2, size_t num_items,
                                   T* d_in1_tmp, R* d_in2_tmp,
                                   T d_in1_max, R d_in2_max) :
                           CubWrapper(num_items), _d_in1(const_cast<T*>(d_in1)),
                           _d_in2(const_cast<R*>(d_in2)),
                           _d_in1_tmp(d_in1_tmp), _d_in2_tmp(d_in2_tmp),
                           _d_in1_max(d_in1_max), _d_in2_max(d_in2_max) {

    auto max = std::max(_d_in1_max, d_in2_max);
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_in2, _d_in2_tmp, _d_in1, _d_in1_tmp,
                                    _num_items, 0, xlib::ceil_log2(max));
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T, typename R>
CubSortPairs2<T, R>::~CubSortPairs2() noexcept {
    if (_internal_alloc)
        cuFree(_d_in1_tmp, _d_in2_tmp);
}

template<typename T, typename R>
void CubSortPairs2<T, R>::run() noexcept {
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_in2, _d_in2_tmp, _d_in1, _d_in1_tmp,
                                    _num_items, 0, xlib::ceil_log2(_d_in2_max));

    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_in1_tmp, _d_in1, _d_in2_tmp, _d_in2,
                                    _num_items, 0, xlib::ceil_log2(_d_in1_max));
}

//------------------------------------------------------------------------------

template<typename T, typename R>
CubRunLengthEncode<T, R>::CubRunLengthEncode(const T* d_in, size_t num_items,
                                             T* d_unique_out, R* d_counts_out)
                                             noexcept :
                           CubWrapper(num_items),
                           _d_in(d_in), _d_unique_out(d_unique_out),
                           _d_counts_out(d_counts_out) {

    cuMalloc(_d_num_runs_out, 1);
    cub::DeviceRunLengthEncode::Encode(_d_temp_storage, _temp_storage_bytes,
                                       _d_in, _d_unique_out, _d_counts_out,
                                       _d_num_runs_out, _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T, typename R>
CubRunLengthEncode<T, R>::~CubRunLengthEncode() noexcept {
    cuFree(_d_num_runs_out);
}

template<typename T, typename R>
int CubRunLengthEncode<T, R>::run() noexcept {
    cub::DeviceRunLengthEncode::Encode(_d_temp_storage, _temp_storage_bytes,
                                       _d_in, _d_unique_out, _d_counts_out,
                                       _d_num_runs_out, _num_items);
    int h_num_runs_out;
    cuMemcpyToHostAsync(_d_num_runs_out, h_num_runs_out);
    return h_num_runs_out;
}

//------------------------------------------------------------------------------

template<typename T>
PartitionFlagged<T>::PartitionFlagged(const T* d_in, const bool* d_flags,
                                      size_t num_items, T* d_out) noexcept :
                                CubWrapper(num_items), _d_in(d_in),
                                _d_flags(d_flags), _d_out(d_out){
    cuMalloc(_d_num_selected_out, 1);
    cub::DevicePartition::Flagged(_d_temp_storage, _temp_storage_bytes, _d_in,
                                  _d_flags, _d_out, _d_num_selected_out,
                                  _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
PartitionFlagged<T>::~PartitionFlagged() noexcept {
    cuFree(_d_num_selected_out);
}

template<typename T>
int PartitionFlagged<T>::run() noexcept {
    CHECK_CUDA_ERROR
    cub::DevicePartition::Flagged(_d_temp_storage, _temp_storage_bytes, _d_in,
                                  _d_flags, _d_out, _d_num_selected_out,
                                  _num_items);
    CHECK_CUDA_ERROR
    int h_num_selected_out;
    cuMemcpyToHostAsync(_d_num_selected_out, h_num_selected_out);
    return h_num_selected_out;
}

//------------------------------------------------------------------------------
template<typename T>
struct SelectOpDiff {
    T diff;
    CUB_RUNTIME_FUNCTION __forceinline__
    SelectOpDiff(const T& diff) noexcept : diff(diff) {}

    //CUB_RUNTIME_FUNCTION __forceinline__
    //bool operator()(const T& item) const { return item != diff; }*/
    CUB_RUNTIME_FUNCTION __forceinline__
    bool operator()(const T& item) const { return item != diff; }
};

template<typename T>
CubSelect<T>::CubSelect(T* d_in_out, size_t num_items) noexcept :
                        CubSelect(d_in_out, num_items, d_in_out) {}

template<typename T>
CubSelect<T>::CubSelect(const T* d_in, size_t num_items, T* d_out) noexcept :
                                CubWrapper(num_items), _d_in(d_in),
                                _d_out(d_out), _num_items(num_items) {
    cuMalloc(_d_num_selected_out, 1);
    T value = T();
    SelectOpDiff<T> select_op(value);
    cub::DeviceSelect::If(_d_temp_storage, _temp_storage_bytes, _d_in,
                          _d_out, _d_num_selected_out, _num_items, select_op);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
CubSelect<T>::~CubSelect() noexcept {
    cuFree(_d_num_selected_out);
}

template<typename T>
int CubSelect<T>::run_diff(const T& diff) noexcept {
    SelectOpDiff<T> select_op(diff);
    cub::DeviceSelect::If(_d_temp_storage, _temp_storage_bytes, _d_in,
                          _d_out, _d_num_selected_out, _num_items, select_op);
    int h_num_selected_out;
    cuMemcpyToHostAsync(_d_num_selected_out, h_num_selected_out);
    return h_num_selected_out;
}

//------------------------------------------------------------------------------

template<typename T>
CubSelectFlagged<T>::CubSelectFlagged(T* d_in_out, size_t num_items,
                                      const bool* d_flags) noexcept :
                    CubSelectFlagged(d_in_out, num_items, d_flags, d_in_out) {}

template<typename T>
CubSelectFlagged<T>::CubSelectFlagged(const T* d_in, size_t num_items,
                                      const bool* d_flags, T* d_out) noexcept :
                                      CubWrapper(num_items), _d_in(d_in),
                                      _d_flags(d_flags), _d_out(d_out),
                                      _num_items(num_items) {
    cuMalloc(_d_num_selected_out, 1);
    cub::DeviceSelect::Flagged(_d_temp_storage, _temp_storage_bytes, _d_in,
                               _d_flags, _d_out, _d_num_selected_out,
                               _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
CubSelectFlagged<T>::~CubSelectFlagged() noexcept {
    cuFree(_d_num_selected_out);
}

template<typename T>
int CubSelectFlagged<T>::run() noexcept {
    cub::DeviceSelect::Flagged(_d_temp_storage, _temp_storage_bytes, _d_in,
                               _d_flags, _d_out, _d_num_selected_out,
                               _num_items);
    int h_num_selected_out;
    cuMemcpyToHostAsync(_d_num_selected_out, h_num_selected_out);
    return h_num_selected_out;
}

//------------------------------------------------------------------------------

template<typename T>
CubReduce<T>::CubReduce(const T* d_in, size_t num_items) noexcept :
                            CubWrapper(num_items), _d_in(d_in) {
    cuMalloc(_d_out, 1);
    cub::DeviceReduce::Sum(_d_temp_storage, _temp_storage_bytes,
                           _d_in, _d_out, _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
T CubReduce<T>::run() noexcept {
    cub::DeviceReduce::Sum(_d_temp_storage, _temp_storage_bytes,
                           _d_in, _d_out, _num_items);
    T h_result;
    cuMemcpyToHostAsync(_d_out, h_result);
    return h_result;
}

template<typename T>
CubReduce<T>::~CubReduce() noexcept {
    cuFree(_d_out);
}
//------------------------------------------------------------------------------

template<typename T>
CubExclusiveSum<T>::CubExclusiveSum(const T* d_in, size_t num_items, T* d_out)
                                    noexcept :
                                        CubWrapper(num_items),
                                        _d_in(d_in), _d_out(d_out) {

    cub::DeviceScan::ExclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_out, _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
CubExclusiveSum<T>::CubExclusiveSum(T* d_in_out, size_t num_items) noexcept :
                             CubExclusiveSum(d_in_out, num_items, d_in_out) {}

template<typename T>
void CubExclusiveSum<T>::run() noexcept {
    cub::DeviceScan::ExclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_out, _num_items);
}

//------------------------------------------------------------------------------
/*
template<typename T>
CubInclusiveSum<T>::CubInclusiveSum(const T* d_in, size_t num_items, T*& d_out) :
                                   CubWrapper(num_items),
                                   _d_in(d_in), _d_out(d_out) {

    cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_out, _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
    cuMalloc(d_out, num_items);
}

template<typename T>
CubInclusiveSum<T>::CubInclusiveSum(T* d_in_out, size_t num_items) :
                                    CubWrapper(num_items),
                                    _d_in(nullptr), _d_out(null_ptr_ref),
                                    _d_in_out(d_in_out) {

    cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  d_in_out, d_in_out, num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
CubInclusiveSum<T>::~CubInclusiveSum() noexcept {
    cuFree(_d_out);
}

template<typename T>
void CubInclusiveSum<T>::run() noexcept {
    if (_d_out != nullptr) {
        cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                      _d_in, _d_out, _num_items);
    }
    else {
        cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                      _d_in_out, _d_in_out, _num_items);
    }
}*/

//------------------------------------------------------------------------------

template<typename T>
CubSegmentedReduce<T>::CubSegmentedReduce(int* d_offsets, const T* d_in,
                                          int num_segments, T*& d_out) :
                                   CubWrapper(num_segments), _d_in(d_in),
                                   _d_out(d_out), _d_offsets(d_offsets) {

    cub::DeviceSegmentedReduce::Sum(_d_temp_storage, _temp_storage_bytes,
                                    _d_in, _d_out, num_segments,
                                    _d_offsets, _d_offsets + 1);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
    cuMalloc(d_out, num_segments);
}

template<typename T>
CubSegmentedReduce<T>::~CubSegmentedReduce() noexcept {
    cuFree(_d_out);
}

template<typename T>
void CubSegmentedReduce<T>::run() noexcept {
    cub::DeviceSegmentedReduce::Sum(_d_temp_storage, _temp_storage_bytes,
                                    _d_in, _d_out, _num_items,
                                    _d_offsets, _d_offsets + 1);
}

//------------------------------------------------------------------------------

template<typename T>
CubSpMV<T>::CubSpMV(T* d_value, int* d_row_offsets, int* d_column_indices,
                    T* d_vector_x, T* d_vector_y,
                    int num_rows, int num_cols, int num_nonzeros) :
                       CubWrapper(0),
                       _d_row_offsets(d_row_offsets),
                       _d_column_indices(d_column_indices),
                       _d_values(d_value),
                       _d_vector_x(d_vector_x), _d_vector_y(d_vector_y),
                       _num_rows(num_rows), _num_cols(num_cols),
                       _num_nonzeros(num_nonzeros) {

    cub::DeviceSpmv::CsrMV(_d_temp_storage, _temp_storage_bytes,
                           _d_values, _d_row_offsets, _d_column_indices,
                           _d_vector_x, _d_vector_y,
                           _num_rows, _num_cols, _num_nonzeros);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}
/*
template<typename T>
CubSpMV<T>::~CubSpMV() noexcept {
    cuFree(_d_out);
}*/

template<typename T>
void CubSpMV<T>::run() noexcept {
    cub::DeviceSpmv::CsrMV(_d_temp_storage, _temp_storage_bytes, _d_values,
                           _d_row_offsets, _d_column_indices,
                           _d_vector_x, _d_vector_y,
                           _num_rows, _num_cols, _num_nonzeros);
}

//------------------------------------------------------------------------------

template<typename T>
CubArgMax<T>::CubArgMax(const T* d_in, size_t num_items) noexcept :
                                    _d_in(d_in), CubWrapper(num_items) {
    cub::KeyValuePair<int, T>* d_tmp;
    cuMalloc(d_tmp, 1);
    cub::DeviceReduce::ArgMax(_d_temp_storage, _temp_storage_bytes, _d_in,
                              static_cast<cub::KeyValuePair<int, T>*>(_d_out),
                              _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
    _d_out = reinterpret_cast<cub::KeyValuePair<int, T>*>(d_tmp);
}

template<typename T>
typename std::pair<int, T>
CubArgMax<T>::run() noexcept {
    cub::DeviceReduce::ArgMax(_d_temp_storage, _temp_storage_bytes, _d_in,
                              static_cast<cub::KeyValuePair<int, T>*>(_d_out),
                              _num_items);
    cub::KeyValuePair<int, T> h_out;
    cuMemcpyToHost(static_cast<cub::KeyValuePair<int, T>*>(_d_out), h_out);
    return std::pair<int, T>(h_out.key, h_out.value);
}

//------------------------------------------------------------------------------

template class CubSortByKey<int, int>;
template class CubSortByKey<double, int>;
template class CubRunLengthEncode<int, int>;
template class CubExclusiveSum<int>;
template class CubSortPairs2<int, int>;
template class PartitionFlagged<int>;
template class CubArgMax<int>;
template class CubSelect<int>;
template class CubSelect<int2>;
template class CubSelectFlagged<int2>;
template class CubSelectFlagged<int>;
template class CubReduce<int>;
template class CubReduce<unsigned>;

} //namespace xlib
