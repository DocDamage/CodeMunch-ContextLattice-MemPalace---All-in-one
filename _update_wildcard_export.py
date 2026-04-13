# Update psm1
with open('module/LLMWorkflow/LLMWorkflow.psm1', 'r', encoding='utf-8') as f:
    content = f.read()

start_text = 'Export-ModuleMember `'
start_idx = content.find(start_text)
if start_idx >= 0:
    new_block = 'Export-ModuleMember -Function * -Alias llmup, llmdown, llmcheck, llmver, llmupdate, llmplugins, llmpalaces, llmsync, llmdashboard, llmheal'
    new_content = content[:start_idx] + new_block
    with open('module/LLMWorkflow/LLMWorkflow.psm1', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('Updated psm1 to wildcard export')
else:
    print('Could not find Export-ModuleMember in psm1')

# Update psd1
with open('module/LLMWorkflow/LLMWorkflow.psd1', 'r', encoding='utf-8') as f:
    psd1_content = f.read()

import re
psd1_content = re.sub(r'FunctionsToExport\s*=\s*@\([^)]*\)', "FunctionsToExport = @('*')", psd1_content, flags=re.DOTALL)

with open('module/LLMWorkflow/LLMWorkflow.psd1', 'w', encoding='utf-8') as f:
    f.write(psd1_content)
print('Updated psd1 to wildcard export')
