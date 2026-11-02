/*
**  Madar Runtime Test Suite
**  Test: BitNet b1.58 Ternary Quantization (I2_S Format)
*/

load "../test_harness.ring"

suite("Madar BitNet b1.58 (I2_S) Engine")

cTestGGUFPath = "test_bitnet_i2s.gguf"

/*
  Header:
  - Magic: "GGUF" (0x46554747)
  - Version: 3 (uint32)
  - Tensor count: 1 (uint64)
  - KV count: 1 (uint64)
*/
cHeader = "GGUF" + u32Bytes(3) + u64Bytes(1) + u64Bytes(1)

/* Metadata KV */
cKV1 = ggufStr("general.architecture") + u32Bytes(8) + ggufStr("bitnet")
cKVs = cKV1

/*
  Tensor Info Table:
  Tensor: "blk.0.weight"
  - n_dims = 1, dims = [128]
  - type = 36 (I2_S)
  - offset = 0
*/
cTensorInfo = ggufStr("blk.0.weight") + u32Bytes(1) + u64Bytes(128) + u32Bytes(36) + u64Bytes(0)

/* Compute padding to 32-byte alignment */
nHeaderLen = len(cHeader) + len(cKVs) + len(cTensorInfo)
nPad = 0
nRem = nHeaderLen % 32
if nRem > 0 {
	nPad = 32 - nRem
}
cPadding = ""
for i = 1 to nPad {
	cPadding += char(0)
}

/*
  Raw Data for 1 Block of I2_S (32 bytes packed + 32 bytes trailing):
  - Byte 0: 0b01100001 (0x61 = 97)
      bits [7:6] = 01 (+1) -> element 0
      bits [5:4] = 10 (-1) -> element 32
      bits [3:2] = 00 ( 0) -> element 64
      bits [1:0] = 01 (+1) -> element 96
  - Bytes 1..31: 0x00 (all zeros)
  - Trailing 32 bytes: scale tail = 1.0 (float32)
*/
cByte0 = char(97) /* 0x61 */
cRestBytes = ""
for i = 1 to 31 {
	cRestBytes += char(0)
}
cTrailing = float2bytes(1.0)
for i = 1 to 28 {
	cTrailing += char(0)
}
cRawData = cByte0 + cRestBytes + cTrailing

/* Write synthetic BitNet GGUF file */
fp = fopen(cTestGGUFPath, "wb")
fwrite(fp, cHeader + cKVs + cTensorInfo + cPadding + cRawData)
fclose(fp)

/*
================================================================================
  Test Cases
================================================================================
*/

/* 1. Open GGUF File */
gguf = gguf_open(cTestGGUFPath)
assert_true(ispointer(gguf), "gguf_open successfully loads BitNet GGUF file")

/* 2. Verify Tensor Type Identification */
tInfo = gguf_tensor_info(gguf, "blk.0.weight")
assert_equal(tInfo[1], "blk.0.weight", "Tensor name is 'blk.0.weight'")
assert_equal(tInfo[2], "I2_S", "Tensor type recognized as 'I2_S' (Type ID 36)")
assert_equal(tInfo[5], 128, "Tensor has exactly 128 elements (1 QK_I2_S block)")

/* 3. Dequantize to F32 Native Tensor */
tF32 = gguf_tensor_to_f32(gguf, "blk.0.weight")
assert_true(istensor(tF32), "Tensor dequantized into native Madar Tensor")
assert_equal(tensor_elements(tF32), 128, "Dequantized tensor contains 128 Float32 elements")

/* 4. Validate Numerical Correctness */
/* Element 0: +1.0 */
assert_equal(1.0, tensor_get(tF32, 1), "Weight 0: +1.0")

/* Element 32: -1.0 */
assert_equal(-1.0, tensor_get(tF32, 33), "Weight 32: -1.0")

/* Element 64: 0.0 */
assert_equal(0.0, tensor_get(tF32, 65), "Weight 64: 0.0")

/* Element 96: +1.0 */
assert_equal(1.0, tensor_get(tF32, 97), "Weight 96: +1.0")

/* Other elements should all be 0.0 */
assert_equal(0.0, tensor_get(tF32, 2), "Weight 1: 0.0")
assert_equal(0.0, tensor_get(tF32, 128), "Weight 127: 0.0")

/* 5. Cleanup */
gguf_close(gguf)
remove(cTestGGUFPath)

test_summary()

/* Helper routines */
func u32Bytes(n) {
	return int2bytes(n)
}

func u64Bytes(n) {
	return int2bytes(n) + int2bytes(0)
}

func ggufStr(s) {
	return u64Bytes(len(s)) + s
}

