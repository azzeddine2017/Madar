# Security Policy

## Supported Versions

We actively support the following versions of RingTensor with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.3.x   | :white_check_mark: |
| 1.2.x   | :white_check_mark: |
| 1.1.x   | :x:                |
| 1.0.x   | :x:                |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take the security of RingTensor seriously. If you discover a security vulnerability, please follow these steps:

### 1. Do Not Publicly Disclose

Please **do not** create a public GitHub issue for security vulnerabilities. This helps protect users who haven't updated yet.

### 2. Report Privately

Send a detailed report to: **azzeddine.remmal@gmail.com**

Include in your report:

- **Description**: Clear description of the vulnerability
- **Impact**: Potential impact and severity
- **Reproduction**: Step-by-step instructions to reproduce
- **Environment**: OS, compiler, Ring version, RingTensor version
- **Proof of Concept**: Code or commands demonstrating the issue (if applicable)
- **Suggested Fix**: If you have ideas for fixing it (optional)

### 3. Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 1-7 days
  - High: 7-14 days
  - Medium: 14-30 days
  - Low: 30-90 days

### 4. Disclosure Process

1. We will acknowledge receipt of your report
2. We will investigate and validate the vulnerability
3. We will develop and test a fix
4. We will release a security patch
5. We will publicly disclose the vulnerability (with credit to you, if desired)

## Security Best Practices

### For Users

1. **Keep Updated**: Always use the latest version
   ```bash
   ringpm update ringtensor
   ```

2. **Validate Inputs**: Sanitize data before passing to tensor operations
   ```ring
   # Check dimensions before operations
   if rows > 0 and cols > 0
       T = tensor_init(rows, cols)
   ok
   ```

3. **Memory Limits**: Set reasonable limits for tensor sizes
   ```ring
   MAX_SIZE = 1000000  # 1 million elements
   if rows * cols > MAX_SIZE
       ? "Tensor too large!"
       return
   ok
   ```

4. **File Validation**: Validate binary files before loading
   ```ring
   # Check file size before loading
   if fsize("model.bin") > 1000000000  # 1GB limit
       ? "File too large!"
       return
   ok
   ```

### For Developers

1. **Bounds Checking**: Always validate array indices
   ```c
   if (row < 0 || row >= t->rows || col < 0 || col >= t->cols) {
       return ERROR_OUT_OF_BOUNDS;
   }
   ```

2. **Memory Safety**: Check allocations and prevent leaks
   ```c
   double *data = (double *)malloc(size * sizeof(double));
   if (!data) {
       return ERROR_OUT_OF_MEMORY;
   }
   ```

3. **Integer Overflow**: Check for overflow in size calculations
   ```c
   if (rows > INT_MAX / cols) {
       return ERROR_OVERFLOW;
   }
   size_t total = (size_t)rows * cols;
   ```

4. **Thread Safety**: Use proper synchronization
   ```c
   #pragma omp critical
   {
       // Critical section
   }
   ```

## Known Security Considerations

### 1. Memory Allocation

**Issue**: Large tensor allocations can exhaust system memory

**Mitigation**:
- Validate tensor sizes before allocation
- Set reasonable limits in your application
- Monitor memory usage

### 2. File Operations

**Issue**: Loading untrusted binary files could cause issues

**Mitigation**:
- Validate file headers and sizes
- Use checksums for model files
- Sanitize file paths

### 3. GPU Operations

**Issue**: GPU operations may expose driver vulnerabilities

**Mitigation**:
- Keep GPU drivers updated
- Validate data before GPU transfer
- Handle GPU errors gracefully

### 4. Numerical Stability

**Issue**: Extreme values can cause numerical instability

**Mitigation**:
- Use gradient clipping
- Validate input ranges
- Check for NaN/Inf values

## Security Checklist

Before deploying RingTensor in production:

- [ ] Using latest stable version
- [ ] Input validation implemented
- [ ] Memory limits configured
- [ ] File validation in place
- [ ] Error handling implemented
- [ ] Logging configured
- [ ] Security updates monitored
- [ ] Dependencies updated

## Vulnerability History

### Version 1.3.2 (Current)
- No known vulnerabilities

### Version 1.3.1
- No known vulnerabilities

### Version 1.2.1
- No known vulnerabilities

### Version 1.2.0
- **Fixed**: Memory leak in graph engine (CVE-NONE-2026-001)
  - Severity: Medium
  - Impact: Memory exhaustion in long-running training
  - Fixed in: 1.2.1

## Security Resources

- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
- **CWE List**: https://cwe.mitre.org/
- **NIST Guidelines**: https://www.nist.gov/cybersecurity

## Contact

For security concerns, contact:

- **Email**: azzeddine.remmal@gmail.com
- **Subject**: [SECURITY] RingTensor Vulnerability Report

For general issues, use GitHub Issues:
- **Issues**: https://github.com/Azzeddine2017/ringtensor/issues

## Acknowledgments

We appreciate responsible disclosure and will credit security researchers who report vulnerabilities (unless they prefer to remain anonymous).

---

**Last Updated**: 2026-01-26  
**Version**: 1.3.2
