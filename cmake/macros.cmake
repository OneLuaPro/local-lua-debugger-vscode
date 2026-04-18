macro(get_cert_fingerprint_sha256 SUBJECT_PATTERN RESULT_VAR)
  set(PS_CMD "$cert = Get-ChildItem Cert:\\CurrentUser\\My | Where-Object { $_.Subject -like '*${SUBJECT_PATTERN}*' } | Select-Object -First 1; if($cert) { $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($cert.RawData); $hash | ForEach-Object { '{0:X2}' -f $_ } | Write-Host -NoNewline }")
  execute_process(
    COMMAND powershell -NoProfile -NonInteractive -Command "${PS_CMD}"
    OUTPUT_VARIABLE ${RESULT_VAR}
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
    COMMAND_ECHO NONE	# for debug: STDOUT
  )
endmacro()
