pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Backs the :app "maven" flavor, which consumes the published
        // io.github.dooop:scummvm AAR instead of the local :scummvm project.
        // GitHub Packages requires authentication to read Maven artifacts even
        // from a public repository, so a token with at least read:packages is
        // needed to resolve it -- see android/README.md.
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/dooop/scummvm")
            credentials {
                username =
                    providers
                        .gradleProperty("gpr.user")
                        .orElse(providers.environmentVariable("GITHUB_ACTOR"))
                        .orNull
                password =
                    providers
                        .gradleProperty("gpr.key")
                        .orElse(providers.environmentVariable("GITHUB_TOKEN"))
                        .orNull
            }
        }
    }
}

rootProject.name = "scummvm"

include(":scummvm")
include(":app")

project(":scummvm").projectDir = file("android/scummvm")
project(":app").projectDir = file("android/app")
