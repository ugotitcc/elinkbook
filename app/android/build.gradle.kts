allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Windows 專屬：本專案位於 U: 磁碟，若某個 Kotlin 原生模組相依套件（例如
// file_picker）的原始碼位於 C: 磁碟的 pub cache，Kotlin 增量編譯器的
// RelocatableFileToPathConverter 計算跨磁碟機代號的相對路徑時會拋出
// 「this and base files have different roots」而編譯失敗。只在偵測到
// Windows 時把 kotlin.incremental 這個 Kotlin Gradle Plugin 讀取的專案屬性
// 設為 false，涵蓋所有子專案（含各個原生外掛模組，例如 :file_picker），
// 避免影響其他平台/CI 的建置效能（見
// docs/epics/epic-1-library/plans/plan-issue-4.md「執行期發現」）。必須在
// subprojects 評估之前、於根專案設定 extra property 才能讓 Kotlin Gradle
// Plugin 的屬性讀取機制在各子專案生效；改用 tasks.withType<KotlinCompile>
// 逐一設定 incremental=false 實測對新版 Kotlin Build Tools API
// （BuildToolsApiCompilationWork）編譯路徑無效，仍會發生同樣的錯誤。
if (System.getProperty("os.name").lowercase().contains("windows")) {
    allprojects {
        extra.set("kotlin.incremental", "false")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
