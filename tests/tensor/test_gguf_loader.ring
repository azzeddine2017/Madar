/*
**  Madar Runtime Test Suite
**  Test: GGUF Model Loader & Native Tensor Integration
*/

load "../test_harness.ring"

suite("Madar GGUF Model Loader")



cTestGGUFPath = "test_model_v3.gguf"

/*
  Header:
  - Magic: "GGUF" (0x46554747)
  - Version: 3 (uint32)
  - Tensor count: 2 (uint64)
  - KV count: 4 (uint64)
*/
cHeader = "GGUF" + u32Bytes(3) + u64Bytes(2) + u64Bytes(4)

/*
  Metadata KVs:
  1. "general.architecture" -> String: "madar-transformer"
  2. "general.name"         -> String: "Madar Tiny Test"
  3. "general.alignment"    -> UInt32: 32
  4. "llama.context_length" -> UInt32: 2048
*/
cKV1 = ggufStr("general.architecture") + u32Bytes(8) + ggufStr("madar-transformer")
cKV2 = ggufStr("general.name")         + u32Bytes(8) + ggufStr("Madar Tiny Test")
cKV3 = ggufStr("general.alignment")    + u32Bytes(4) + u32Bytes(32)
cKV4 = ggufStr("llama.context_length") + u32Bytes(4) + u32Bytes(2048)
cKVs = cKV1 + cKV2 + cKV3 + cKV4

/*
  Tensors Info Table:
  Tensor 1: "weight"
  - n_dims = 2, dims = [2, 3] (6 elements)
  - type = 0 (F32)
  - offset = 0 (uint64)
  Tensor 2: "bias"
  - n_dims = 1, dims = [2] (2 elements)
  - type = 0 (F32)
  - offset = 24 (6 * 4 = 24 bytes, uint64)
*/
cTensor1Info = ggufStr("weight") + u32Bytes(2) + u64Bytes(2) + u64Bytes(3) + u32Bytes(0) + u64Bytes(0)
cTensor2Info = ggufStr("bias")   + u32Bytes(1) + u64Bytes(2)                + u32Bytes(0) + u64Bytes(24)
cTensorsInfo = cTensor1Info + cTensor2Info

/* Compute padding to alignment (32 bytes) */
nHeaderLen = len(cHeader) + len(cKVs) + len(cTensorsInfo)
nPad = 0
nRem = nHeaderLen % 32
if nRem > 0
	nPad = 32 - nRem
ok
cPadding = ""
for i = 1 to nPad
	cPadding += char(0)
next

/*
  Tensor Raw Data:
  Tensor 1 (weight, 6 floats): 1.0, 2.0, 3.0, 4.0, 5.0, 6.0
  Tensor 2 (bias, 2 floats):   10.0, 20.0
*/
cDataWeight = float2bytes(1.0) + float2bytes(2.0) + float2bytes(3.0) + float2bytes(4.0) + float2bytes(5.0) + float2bytes(6.0)
cDataBias   = float2bytes(10.0) + float2bytes(20.0)
cRawData = cDataWeight + cDataBias

/* Write test GGUF file to disk */
fp = fopen(cTestGGUFPath, "wb")
fwrite(fp, cHeader + cKVs + cTensorsInfo + cPadding + cRawData)
fclose(fp)

/*
================================================================================
  Test Cases
================================================================================
*/

/* 1. Open GGUF Model File */
gguf = gguf_open(cTestGGUFPath)
assert_true(ispointer(gguf), "gguf_open returns a valid model handle")

/* 2. Header Attributes */
assert_equal(gguf_version(gguf), 3, "GGUF file version is 3")
assert_equal(gguf_tensor_count(gguf), 2, "Tensor count is 2")
assert_equal(gguf_metadata_count(gguf), 4, "Metadata KV count is 4")
assert_equal(gguf_alignment(gguf), 32, "Data section alignment is 32 bytes")

/* 3. Metadata Extraction */
assert_equal(gguf_architecture(gguf), "madar-transformer", "Architecture matches 'madar-transformer'")
assert_equal(gguf_metadata_get(gguf, "general.name"), "Madar Tiny Test", "Model name metadata matches")
assert_equal(gguf_metadata_get(gguf, "llama.context_length"), 2048, "Context length metadata matches 2048")

keys = gguf_metadata_keys(gguf)
assert_equal(len(keys), 4, "Metadata keys list has 4 elements")
assert_true(find(keys, "general.architecture") > 0, "Keys contains 'general.architecture'")
assert_true(find(keys, "llama.context_length") > 0, "Keys contains 'llama.context_length'")

/* 4. Tensor Information & Inspection */
tNames = gguf_tensor_names(gguf)
assert_equal(len(tNames), 2, "Tensor names list has 2 elements")
assert_equal(tNames[1], "weight", "First tensor name is 'weight'")
assert_equal(tNames[2], "bias", "Second tensor name is 'bias'")

infoWeight = gguf_tensor_info(gguf, "weight")
assert_equal(infoWeight[1], "weight", "infoWeight name is 'weight'")
assert_equal(infoWeight[2], "F32", "infoWeight type is 'F32'")
assert_equal(infoWeight[3], 2, "infoWeight rank is 2")
assert_equal(infoWeight[5], 6, "infoWeight element count is 6")

infoBias = gguf_tensor_info(gguf, "bias")
assert_equal(infoBias[1], "bias", "infoBias name is 'bias'")
assert_equal(infoBias[2], "F32", "infoBias type is 'F32'")
assert_equal(infoBias[3], 1, "infoBias rank is 1")
assert_equal(infoBias[5], 2, "infoBias element count is 2")

/* 5. Load Native Tensors & Verify Raw Elements */
tWeight = gguf_tensor_get(gguf, "weight")
assert_true(istensor(tWeight), "tWeight is loaded as a native Madar Tensor")
assert_equal(tensor_elements(tWeight), 6, "tWeight has 6 elements")
assert_equal(tensor_get(tWeight, 1, 1), 1.0, "tWeight[1, 1] = 1.0")
assert_equal(tensor_get(tWeight, 1, 2), 2.0, "tWeight[1, 2] = 2.0")
assert_equal(tensor_get(tWeight, 2, 3), 6.0, "tWeight[2, 3] = 6.0")

tBias = gguf_tensor_to_f32(gguf, "bias")
assert_true(istensor(tBias), "tBias is loaded as a native F32 Tensor")
assert_equal(tensor_elements(tBias), 2, "tBias has 2 elements")
assert_equal(tensor_get(tBias, 1), 10.0, "tBias[1] = 10.0")
assert_equal(tensor_get(tBias, 2), 20.0, "tBias[2] = 20.0")

/* 6. Perform Vectorized Math Directly on Loaded GGUF Tensor */
tDouble = tWeight * 2.0
assert_equal(tensor_get(tDouble, 1, 1), 2.0, "GGUF tensor arithmetic: 1.0 * 2 = 2.0")
assert_equal(tensor_get(tDouble, 2, 3), 12.0, "GGUF tensor arithmetic: 6.0 * 2 = 12.0")

/* 7. Close and Cleanup */
gguf_close(gguf)
remove(cTestGGUFPath)

test_summary()

/*
================================================================================
  Helper: Create Synthetic GGUF v3 Model File for Testing
================================================================================
*/

func u32Bytes(n)
	return int2bytes(n)

func u64Bytes(n)
	return int2bytes(n) + int2bytes(0)

func ggufStr(s)
	return u64Bytes(len(s)) + s