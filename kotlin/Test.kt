// Runs the Kotlin implementation against the conformance vectors and every
// document in the repository.
//
//   kotlinc kotlin/Springwater.kt kotlin/Test.kt -include-runtime -d /tmp/springwater-test.jar
//   kotlin -cp /tmp/springwater-test.jar springwater.TestKt .
//
// The argument is the repository root. kotlin/vectors.tsv is generated from
// tools/conformance_vectors.json by kotlin/make_vectors.js.

package springwater

import java.io.File
import java.util.Base64

private fun dump(node: Node, out: MutableList<String>) {
    when (node) {
        is Content -> {
            val text = Base64.getEncoder().encodeToString(node.text.toByteArray(Charsets.UTF_8))
            out.add("=" + node.ending.name.lowercase() + " " + text)
        }
        is Element -> {
            out.add("<" + node.name)
            for (child in node.children) dump(child, out)
            out.add(">")
        }
    }
}

private fun springwaterFiles(repo: File, dir: String): List<File> {
    val files = File(repo, dir).listFiles() ?: return emptyList()
    return files.filter { it.name.endsWith(".springwater") }.sortedBy { it.name }
}

fun main(args: Array<String>) {
    val repo = File(if (args.isNotEmpty()) args[0] else ".")
    val decoder = Base64.getDecoder()
    var failures = 0
    var passed = 0

    // 1. Conformance vectors.
    for (line in File(repo, "kotlin/vectors.tsv").readLines()) {
        if (line.isEmpty()) continue
        val f = line.split("\t")
        if (f[0] == "P") {
            val input = if (f[2] == "-") ByteArray(0) else decoder.decode(f[2])
            val got = try {
                val out = ArrayList<String>()
                dump(Springwater.parse(input), out)
                "tree:" + out.joinToString("|")
            } catch (e: SpringwaterException) {
                "error:" + e.kind
            }
            if (got == f[3]) passed += 1 else { failures += 1; println("FAIL parse vector: " + f[1] + " (got " + got.take(80) + ")") }
        } else if (f[0] == "C") {
            val text = String(decoder.decode(f[1]), Charsets.UTF_8)
            val c = Springwater.classify(Springwater.trimmed(text))
            val got = c.kind.name.lowercase() + ":" + (c.name ?: "-")
            if (got == f[2]) passed += 1 else { failures += 1; println("FAIL classify vector: " + text + " (got " + got + ")") }
        }
    }
    println("conformance vectors: $passed passed")

    // 2. Repository documents: parse, canonical round trip, schema validity.
    val schemaFiles = springwaterFiles(repo, "schemas")
    val meta = Schema.from(Springwater.parse(File(repo, "schemas/schema.schema.springwater").readBytes()))
    val byRoot = HashMap<String, Schema>()
    for (file in schemaFiles) {
        if (file.name == "schema.schema.springwater") continue
        val schema = Schema.from(Springwater.parse(file.readBytes()))
        byRoot[schema.requiredRoot] = schema
    }
    val documents = schemaFiles + springwaterFiles(repo, "examples") + springwaterFiles(repo, "profiles") +
        springwaterFiles(repo, "presentations") + listOf(File(repo, "ROSETTA.springwater"))
    for (file in documents) {
        val bytes = file.readBytes()
        val root = Springwater.parse(bytes)
        if (Springwater.serialize(root) != String(bytes, Charsets.UTF_8)) {
            failures += 1; println("FAIL canonical round trip: " + file.name)
        }
        val isSchema = file.parentFile.name == "schemas"
        val first = root.childElements.firstOrNull()
        val schema = if (isSchema) meta else byRoot[first?.name ?: ""]
        if (schema == null) {
            failures += 1; println("FAIL no schema for " + file.name)
            continue
        }
        val issues = schema.validate(root)
        if (issues.isNotEmpty()) { failures += 1; println("FAIL " + file.name + ": " + issues.take(3).joinToString("; ")) }
    }
    println("repository documents: ${documents.size} checked")

    println(if (failures == 0) "all checks passed" else "$failures failure(s)")
    if (failures != 0) System.exit(1)
}
