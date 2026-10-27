// Exporta o pseudocódigo C de TODAS as funções do programa (Ghidra headless).
// Uso: analyzeHeadless <proj> <nome> -import <bin> -scriptPath <esta pasta>
//        -postScript ExportarTudo.java <pasta_saida> -deleteProject
// Saída: <pasta_saida>/<binario>.c (todas as funções, em ordem de endereço)
//        <pasta_saida>/<binario>.funcoes.tsv (endereço, nome, tamanho, strings usadas)
//        <pasta_saida>/<binario>.strings.tsv (strings definidas e quem as usa)
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.address.*;
import ghidra.program.model.data.StringDataInstance;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class ExportarTudo extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        File out = new File(args[0]);
        out.mkdirs();
        String base = currentProgram.getName();
        Listing listing = currentProgram.getListing();
        ReferenceManager refs = currentProgram.getReferenceManager();
        FunctionManager fm = currentProgram.getFunctionManager();

        // strings definidas e funções que as referenciam
        Map<Function, List<String>> strsPorFunc = new HashMap<>();
        try (PrintWriter sw = new PrintWriter(new OutputStreamWriter(
                new FileOutputStream(new File(out, base + ".strings.tsv")), StandardCharsets.UTF_8))) {
            sw.println("endereco\tusada_por\tvalor");
            DataIterator it = listing.getDefinedData(true);
            while (it.hasNext() && !monitor.isCancelled()) {
                Data d = it.next();
                StringDataInstance sdi = StringDataInstance.getStringDataInstance(d);
                if (sdi == null || sdi == StringDataInstance.NULL_INSTANCE) continue;
                String v = sdi.getStringValue();
                if (v == null) continue;
                String limpa = v.replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n");
                Set<String> usos = new TreeSet<>();
                for (Reference r : refs.getReferencesTo(d.getAddress())) {
                    Function f = fm.getFunctionContaining(r.getFromAddress());
                    if (f == null) continue;
                    usos.add(f.getEntryPoint().toString());
                    strsPorFunc.computeIfAbsent(f, k -> new ArrayList<>()).add(limpa);
                }
                sw.println(d.getAddress() + "\t" + String.join(",", usos) + "\t" + limpa);
            }
        }

        DecompInterface di = new DecompInterface();
        DecompileOptions opt = new DecompileOptions();
        di.setOptions(opt);
        di.openProgram(currentProgram);

        int total = 0, falhas = 0;
        try (PrintWriter cw = new PrintWriter(new OutputStreamWriter(
                     new FileOutputStream(new File(out, base + ".c")), StandardCharsets.UTF_8));
             PrintWriter fw = new PrintWriter(new OutputStreamWriter(
                     new FileOutputStream(new File(out, base + ".funcoes.tsv")), StandardCharsets.UTF_8))) {
            cw.println("// Pseudocódigo Ghidra de " + base + " (todas as funções). Gerado por ExportarTudo.java.");
            cw.println("// sha256 " + currentProgram.getExecutableSHA256());
            fw.println("endereco\tnome\tbytes\tstrings");
            FunctionIterator fi = fm.getFunctions(true);
            while (fi.hasNext() && !monitor.isCancelled()) {
                Function f = fi.next();
                if (f.isExternal() || f.isThunk()) continue;
                total++;
                List<String> ss = strsPorFunc.getOrDefault(f, Collections.emptyList());
                String resumo = String.join(" | ", ss);
                if (resumo.length() > 400) resumo = resumo.substring(0, 400) + "...";
                fw.println(f.getEntryPoint() + "\t" + f.getName() + "\t" + f.getBody().getNumAddresses() + "\t" + resumo);
                cw.println();
                cw.println("// ==== " + f.getName() + " @ " + f.getEntryPoint());
                for (String s : ss.subList(0, Math.min(ss.size(), 12))) {
                    cw.println("//   str: " + (s.length() > 160 ? s.substring(0, 160) + "..." : s));
                }
                DecompileResults r = di.decompileFunction(f, 60, monitor);
                if (r != null && r.decompileCompleted() && r.getDecompiledFunction() != null) {
                    cw.println(r.getDecompiledFunction().getC());
                } else {
                    falhas++;
                    cw.println("// falha na descompilação: " + (r == null ? "null" : r.getErrorMessage()));
                }
            }
        }
        di.dispose();
        println("ExportarTudo: " + base + " funcoes=" + total + " falhas=" + falhas);
    }
}
