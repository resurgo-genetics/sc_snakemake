import os
from utils.parse import read_quants, read_qcs
from utils.file_control import create_file_targets

# Get the metadata from irods
metadata_file = os.path.join(config['tmp_folder'], 'items.json')
with open(metadata_file) as fh:
    items = json.load(fh)

FASTQ_FOLDER = config['fastq_folder']
LUSTRE = config['lustre_folder']
RESULTS_FOLDER = config['results_folder']
CRAM_FOLDER = config['cram_folder']
LOG_FOLDER = config['log_folder']

# item_dict = {q['data_object']: q['avus'] for q in items]}
merge_mapper = {}
glob_variables = glob_wildcards(os.path.join(config['cram_folder'], 
                           config['pattern'] + '.cram'))

final_samples, merge_mapper = create_file_targets(glob_variables, config)

rule all:
    input:
        os.path.join(RESULTS_FOLDER, "results", "tpm.csv"),
        os.path.join(RESULTS_FOLDER, "qc", "multiqc_salmon", "multiqc_report.html"),
        os.path.join(RESULTS_FOLDER, "qc", "salmon_qc.csv")

rule multiqc_salmon:
    input:
        expand(os.path.join(RESULTS_FOLDER, "quant", "{sample}", 
               "quant.genes.sf"), sample=final_samples)
    output:
        os.path.join(RESULTS_FOLDER, "qc", "multiqc_salmon", "multiqc_report.html")
    log:
        os.path.join(LOG_FOLDER, "multiqc_salmon.log")
    shell:
        "multiqc {salmon_results} -o {out_folder}".format(
            salmon_results=os.path.join(RESULTS_FOLDER, "quant"),
            out_folder = os.path.join(RESULTS_FOLDER, "qc", "multiqc_salmon"))

rule read_salmon_qcs:
    input:
        expand(os.path.join(RESULTS_FOLDER, "quant", "{sample}", 
               "quant.genes.sf"), sample=final_samples)
    output:
        os.path.join(RESULTS_FOLDER, "qc", "salmon_qc.csv"),
    log:
        os.path.join(LOG_FOLDER, "parsing", "salmon_qc.log")
    run:
        qcs = read_qcs(pattern=os.path.join(RESULTS_FOLDER, "quant", "*"))
        qcs.to_csv(output[0])

rule read_reads:
    input:
        expand(os.path.join(RESULTS_FOLDER, "quant", "{sample}", 
               "quant.genes.sf"), sample=final_samples)
    output:
        os.path.join(RESULTS_FOLDER, "results", "reads.csv")
    log:
        os.path.join(LOG_FOLDER, "parsing", "reads.log")
    run:
        results = read_quants(os.path.join(RESULTS_FOLDER, "quant", "*"), 
                              cols=["NumReads"])
        results.to_csv(output[0])

rule read_tpm:
    input:
        expand(os.path.join(RESULTS_FOLDER, "quant", "{sample}", 
               "quant.genes.sf"), sample=final_samples)
    output:
        os.path.join(RESULTS_FOLDER, "results", "tpm.csv"),
    log:
        os.path.join(LOG_FOLDER, "parsing", "tpm.log")
    run:
        results = read_quants(pattern=os.path.join(RESULTS_FOLDER, "quant", "*"))
        results.to_csv(output[0])

rule quantify:
    input:
        forward=os.path.join(LUSTRE, "{sample}_forward.fastq"),
        reverse=os.path.join(LUSTRE, "{sample}_reverse.fastq")
    output:
        os.path.join(RESULTS_FOLDER, "quant", "{sample}", "quant.genes.sf")
    log:
        lambda wildcards: os.path.join(
            LOG_FOLDER, "salmon", "{sample}.log".format(sample=wildcards.sample))
    params:
        out_folder=lambda wildcards: os.path.join(RESULTS_FOLDER, "quant",
                                                  wildcards.sample)
    shell:
        "salmon quant -i /nfs/team205/.scapi/references/human/salmon_index "
        "-g /nfs/team205/.scapi/references/human/human_gene_map.txt "
        "-l IU -1 {input.forward} -2 {input.reverse} -o "
        "{params.out_folder}"

rule copy_unmerged_forward:
    input:
        lambda wildcards: os.path.join(
            FASTQ_FOLDER,
            "{sample}_forward.fastq".format(sample=wildcards.sample))
    output:
        temp(os.path.join(LUSTRE, "{sample}_forward.fastq"))
    shell:
        "cp {input} {output}"

rule copy_unmerged_reverse:
    input:
        lambda wildcards: os.path.join(
            FASTQ_FOLDER,
            "{sample}_reverse.fastq".format(sample=wildcards.sample))
    output:
        temp(os.path.join(LUSTRE, "{sample}_reverse.fastq"))
    shell:
        "cp {input} {output}"

rule merge_reverse:
    input:
        lambda wildcards: [
            os.path.join(FASTQ_FOLDER, 
                         "{original_sample}_reverse.fastq".format(
                           original_sample=merge_mapper[wildcards.sample][0])),
            os.path.join(FASTQ_FOLDER, 
                         "{original_sample}_reverse.fastq".format(
                           original_sample=merge_mapper[wildcards.sample][1]))]
    output:
        temp(os.path.join(LUSTRE, "{sample}_reverse.fastq"))
    log:
        lambda wildcards: os.path.join(
            LOG_FOLDER, "merge", "{sample}.log".format(sample=wildcards.sample))
    shell:
        "cat {input} > {output}"

rule merge_forward:
    input:
        lambda wildcards: [
            os.path.join(
                FASTQ_FOLDER, "{original_sample}_forward.fastq".format(
                    original_sample=merge_mapper[wildcards.sample][0])),
            os.path.join(
                FASTQ_FOLDER, "{original_sample}_forward.fastq".format(
                    original_sample=merge_mapper[wildcards.sample][1]))]
    output:
        temp(os.path.join(LUSTRE, "{sample}_forward.fastq"))
    log:
        lambda wildcards: os.path.join(
            LOG_FOLDER, "merge", "{sample}.log".format(sample=wildcards.sample))
    shell:
        "cat {input} > {output}"

rule convert_fastq:
    input:
        lambda wildcards: [
            os.path.join(CRAM_FOLDER, "{original_sample}.cram".format(
                original_sample=wildcards.original_sample))]
    output:
        forward=os.path.join(FASTQ_FOLDER, "{original_sample}_forward.fastq"),
        reverse=os.path.join(FASTQ_FOLDER, "{original_sample}_reverse.fastq")
    log:
        os.path.join(LOG_FOLDER, "fastq_conversion", "{original_sample}.log")
    shell:
        "samtools sort -m 10G -n -T %s {input} | "
        "samtools fastq -F 0xB00 -1 {output.forward} -2 {output.reverse} -"

