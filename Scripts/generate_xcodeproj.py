#!/usr/bin/env python3
"""Génère App/VeloBoucle.xcodeproj à partir de l'arborescence des sources.

POURQUOI CE SCRIPT
------------------
Ce dépôt est développé depuis Linux, où Xcode n'existe pas : le fichier
`project.pbxproj` ne peut donc pas être produit par l'interface graphique.
Le générer permet aussi de le régénérer sans effort après avoir ajouté des
fichiers, et d'éviter les conflits de fusion illisibles propres à ce format.

Le projet produit est un projet Xcode ordinaire : une fois généré, il s'ouvre,
se modifie et se compile normalement. Rien n'oblige à réexécuter ce script.

STRUCTURE PRODUITE
------------------
  VeloBoucle          application iOS 17+ (SwiftUI, MapKit, CoreLocation, SwiftData)
  VeloBoucleTests     tests unitaires de la couche application
  VeloBoucleUITests   tests d'interface (XCUITest)
  VeloCore            paquet Swift local (../Core), dépendance de l'application

Usage : python3 Scripts/generate_xcodeproj.py
"""

from __future__ import annotations

import hashlib
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = REPO_ROOT / "App"
PROJECT_PATH = APP_DIR / "VeloBoucle.xcodeproj"

APP_TARGET = "VeloBoucle"
UNIT_TEST_TARGET = "VeloBoucleTests"
UI_TEST_TARGET = "VeloBoucleUITests"
BUNDLE_ID = "ch.veloboucle.app"
LANGUAGES = ["fr", "en", "de"]


def object_id(*parts: str) -> str:
    """Identifiant stable de 24 caractères hexadécimaux.

    Xcode n'exige que l'unicité. Les dériver d'un hachage rend le fichier
    reproductible : régénérer sans changement ne produit aucune différence.
    """
    digest = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def swift_sources(directory: Path) -> list[Path]:
    """Fichiers Swift d'un dossier, triés, chemins relatifs à App/."""
    return sorted(
        (path.relative_to(APP_DIR) for path in directory.rglob("*.swift")),
        key=str,
    )


class ProjectWriter:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def add(self, text: str = "") -> None:
        self.lines.append(text)

    def render(self) -> str:
        return "\n".join(self.lines) + "\n"


def build_group_tree(paths: list[Path]) -> dict:
    """Arborescence imbriquée {nom_dossier: sous-arbre, "__files__": [...]}"""
    tree: dict = {"__files__": []}
    for path in paths:
        node = tree
        for part in path.parts[:-1]:
            node = node.setdefault(part, {"__files__": []})
        node["__files__"].append(path)
    return tree


def main() -> int:
    app_sources = swift_sources(APP_DIR / APP_TARGET)
    unit_test_sources = swift_sources(APP_DIR / UNIT_TEST_TARGET)
    ui_test_sources = swift_sources(APP_DIR / UI_TEST_TARGET)

    if not app_sources:
        raise SystemExit("Aucune source Swift trouvée dans App/VeloBoucle")

    resources_dir = APP_DIR / APP_TARGET / "Resources"
    assets_path = Path(APP_TARGET) / "Resources" / "Assets.xcassets"
    info_plist_path = Path(APP_TARGET) / "Resources" / "Info.plist"
    has_localizations = any(
        (resources_dir / f"{language}.lproj" / "Localizable.strings").exists()
        for language in LANGUAGES
    )

    writer = ProjectWriter()
    writer.add("// !$*UTF8*$!")
    writer.add("{")
    writer.add("\tarchiveVersion = 1;")
    writer.add("\tclasses = {")
    writer.add("\t};")
    # 56 = format des projets Xcode 14/15, lisible par toutes les versions
    # récentes et le plus stable pour un fichier écrit à la main.
    writer.add("\tobjectVersion = 56;")
    writer.add("\tobjects = {")

    # ------------------------------------------------------------------ files
    file_refs: dict[str, str] = {}          # chemin relatif -> id
    build_files: dict[tuple[str, str], str] = {}  # (cible, chemin) -> id

    def file_ref_id(relative: str) -> str:
        if relative not in file_refs:
            file_refs[relative] = object_id("fileRef", relative)
        return file_refs[relative]

    def build_file_id(target: str, relative: str) -> str:
        key = (target, relative)
        if key not in build_files:
            build_files[key] = object_id("buildFile", target, relative)
        return build_files[key]

    writer.add("")
    writer.add("/* Begin PBXBuildFile section */")
    for target, sources in (
        (APP_TARGET, app_sources),
        (UNIT_TEST_TARGET, unit_test_sources),
        (UI_TEST_TARGET, ui_test_sources),
    ):
        for source in sources:
            relative = str(source)
            writer.add(
                f"\t\t{build_file_id(target, relative)} /* {source.name} in Sources */ = "
                f"{{isa = PBXBuildFile; fileRef = {file_ref_id(relative)} /* {source.name} */; }};"
            )

    # Ressources de l'application.
    assets_relative = str(assets_path)
    writer.add(
        f"\t\t{build_file_id(APP_TARGET, assets_relative)} /* Assets.xcassets in Resources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ref_id(assets_relative)} /* Assets.xcassets */; }};"
    )
    if has_localizations:
        variant_group_id = object_id("variantGroup", "Localizable.strings")
        writer.add(
            f"\t\t{build_file_id(APP_TARGET, 'Localizable.strings')} "
            f"/* Localizable.strings in Resources */ = {{isa = PBXBuildFile; "
            f"fileRef = {variant_group_id} /* Localizable.strings */; }};"
        )

    # Dépendance au paquet local VeloCore.
    velo_core_product_id = object_id("packageProduct", "VeloCore")
    writer.add(
        f"\t\t{object_id('buildFile', 'VeloCore')} /* VeloCore in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {velo_core_product_id} /* VeloCore */; }};"
    )
    # Les tests unitaires utilisent aussi VeloCore, via l'application hôte.
    velo_core_test_product_id = object_id("packageProduct", "VeloCoreTests")
    writer.add(
        f"\t\t{object_id('buildFile', 'VeloCoreForTests')} /* VeloCore in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {velo_core_test_product_id} /* VeloCore */; }};"
    )
    writer.add("/* End PBXBuildFile section */")

    # -------------------------------------------------------------- proxies
    app_target_id = object_id("target", APP_TARGET)
    unit_target_id = object_id("target", UNIT_TEST_TARGET)
    ui_target_id = object_id("target", UI_TEST_TARGET)
    project_id = object_id("project", "VeloBoucle")

    writer.add("")
    writer.add("/* Begin PBXContainerItemProxy section */")
    for name, target_id in ((UNIT_TEST_TARGET, unit_target_id), (UI_TEST_TARGET, ui_target_id)):
        writer.add(f"\t\t{object_id('proxy', name)} /* PBXContainerItemProxy */ = {{")
        writer.add("\t\t\tisa = PBXContainerItemProxy;")
        writer.add(f"\t\t\tcontainerPortal = {project_id} /* Project object */;")
        writer.add("\t\t\tproxyType = 1;")
        writer.add(f"\t\t\tremoteGlobalIDString = {app_target_id};")
        writer.add(f"\t\t\tremoteInfo = {APP_TARGET};")
        writer.add("\t\t};")
    writer.add("/* End PBXContainerItemProxy section */")

    # ----------------------------------------------------------- file refs
    product_ids = {
        APP_TARGET: object_id("product", APP_TARGET),
        UNIT_TEST_TARGET: object_id("product", UNIT_TEST_TARGET),
        UI_TEST_TARGET: object_id("product", UI_TEST_TARGET),
    }
    config_files = {
        "Debug": "Config/Debug.xcconfig",
        "Release": "Config/Release.xcconfig",
        "Base": "Config/Base.xcconfig",
    }

    writer.add("")
    writer.add("/* Begin PBXFileReference section */")
    for relative, identifier in sorted(file_refs.items(), key=lambda item: item[0]):
        name = Path(relative).name
        if name.endswith(".swift"):
            file_type = "sourcecode.swift"
        elif name.endswith(".xcassets"):
            file_type = "folder.assetcatalog"
        else:
            file_type = "text"
        writer.add(
            f"\t\t{identifier} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type}; path = \"{name}\"; sourceTree = \"<group>\"; }};"
        )

    writer.add(
        f"\t\t{file_ref_id(str(info_plist_path))} /* Info.plist */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
    )
    for label, path in config_files.items():
        writer.add(
            f"\t\t{object_id('config', label)} /* {Path(path).name} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = text.xcconfig; "
            f"path = {Path(path).name}; sourceTree = \"<group>\"; }};"
        )
    if has_localizations:
        for language in LANGUAGES:
            writer.add(
                f"\t\t{object_id('strings', language)} /* {language} */ = "
                f"{{isa = PBXFileReference; lastKnownFileType = text.plist.strings; "
                f"name = {language}; path = {language}.lproj/Localizable.strings; "
                f"sourceTree = \"<group>\"; }};"
            )

    writer.add(
        f"\t\t{product_ids[APP_TARGET]} /* VeloBoucle.app */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.application; includeInIndex = 0; "
        "path = VeloBoucle.app; sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    for name in (UNIT_TEST_TARGET, UI_TEST_TARGET):
        writer.add(
            f"\t\t{product_ids[name]} /* {name}.xctest */ = {{isa = PBXFileReference; "
            "explicitFileType = wrapper.cfbundle; includeInIndex = 0; "
            f"path = {name}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
        )
    writer.add("/* End PBXFileReference section */")

    # ------------------------------------------------------- variant group
    if has_localizations:
        writer.add("")
        writer.add("/* Begin PBXVariantGroup section */")
        writer.add(f"\t\t{variant_group_id} /* Localizable.strings */ = {{")
        writer.add("\t\t\tisa = PBXVariantGroup;")
        writer.add("\t\t\tchildren = (")
        for language in LANGUAGES:
            writer.add(f"\t\t\t\t{object_id('strings', language)} /* {language} */,")
        writer.add("\t\t\t);")
        writer.add("\t\t\tname = Localizable.strings;")
        writer.add("\t\t\tsourceTree = \"<group>\";")
        writer.add("\t\t};")
        writer.add("/* End PBXVariantGroup section */")

    # -------------------------------------------------------------- groups
    writer.add("")
    writer.add("/* Begin PBXGroup section */")

    # Fichiers rattachés à un groupe sans être des sources Swift : catalogue
    # d'assets, Info.plist et catalogue de traductions vivent tous dans
    # `VeloBoucle/Resources`.
    extra_children_by_prefix: dict[str, list[str]] = {
        f"{APP_TARGET}/Resources": [
            f"\t\t\t\t{file_ref_id(assets_relative)} /* Assets.xcassets */,",
            f"\t\t\t\t{file_ref_id(str(info_plist_path))} /* Info.plist */,",
        ]
    }
    if has_localizations:
        extra_children_by_prefix[f"{APP_TARGET}/Resources"].append(
            f"\t\t\t\t{variant_group_id} /* Localizable.strings */,"
        )

    def emit_group(prefix: str, name: str, tree: dict) -> str:
        """Émet un PBXGroup et ses descendants.

        `prefix` est le chemin du groupe relatif à `App/` ; c'est aussi la clé
        sous laquelle les fichiers sont enregistrés, ce qui garantit que les
        identifiants émis ici sont exactement ceux déclarés dans la section
        PBXFileReference.
        """
        group_id = object_id("group", prefix)
        children: list[str] = []

        for key in sorted(k for k in tree if k != "__files__"):
            child_id = emit_group(f"{prefix}/{key}", key, tree[key])
            children.append(f"\t\t\t\t{child_id} /* {key} */,")

        for path in tree["__files__"]:
            children.append(f"\t\t\t\t{file_ref_id(str(path))} /* {path.name} */,")

        children.extend(extra_children_by_prefix.get(prefix, []))

        writer.add(f"\t\t{group_id} /* {name} */ = {{")
        writer.add("\t\t\tisa = PBXGroup;")
        writer.add("\t\t\tchildren = (")
        for child in children:
            writer.add(child)
        writer.add("\t\t\t);")
        writer.add(f"\t\t\tpath = {name};")
        writer.add("\t\t\tsourceTree = \"<group>\";")
        writer.add("\t\t};")
        return group_id

    # L'arbre est construit sur les chemins complets relatifs à `App/`, dont la
    # première composante est le nom de la cible.
    app_tree = build_group_tree(app_sources)[APP_TARGET]
    app_group_id = emit_group(APP_TARGET, APP_TARGET, app_tree)

    def emit_flat_group(name: str, sources: list[Path]) -> str:
        group_id = object_id("group", name)
        writer.add(f"\t\t{group_id} /* {name} */ = {{")
        writer.add("\t\t\tisa = PBXGroup;")
        writer.add("\t\t\tchildren = (")
        for source in sources:
            writer.add(f"\t\t\t\t{file_ref_id(str(source))} /* {source.name} */,")
        writer.add("\t\t\t);")
        writer.add(f"\t\t\tpath = {name};")
        writer.add("\t\t\tsourceTree = \"<group>\";")
        writer.add("\t\t};")
        return group_id

    unit_group_id = emit_flat_group(UNIT_TEST_TARGET, unit_test_sources)
    ui_group_id = emit_flat_group(UI_TEST_TARGET, ui_test_sources)

    config_group_id = object_id("group", "Config")
    writer.add(f"\t\t{config_group_id} /* Config */ = {{")
    writer.add("\t\t\tisa = PBXGroup;")
    writer.add("\t\t\tchildren = (")
    for label in ("Base", "Debug", "Release"):
        writer.add(f"\t\t\t\t{object_id('config', label)} /* {label}.xcconfig */,")
    writer.add("\t\t\t);")
    writer.add("\t\t\tpath = Config;")
    writer.add("\t\t\tsourceTree = \"<group>\";")
    writer.add("\t\t};")

    products_group_id = object_id("group", "Products")
    writer.add(f"\t\t{products_group_id} /* Products */ = {{")
    writer.add("\t\t\tisa = PBXGroup;")
    writer.add("\t\t\tchildren = (")
    writer.add(f"\t\t\t\t{product_ids[APP_TARGET]} /* VeloBoucle.app */,")
    writer.add(f"\t\t\t\t{product_ids[UNIT_TEST_TARGET]} /* {UNIT_TEST_TARGET}.xctest */,")
    writer.add(f"\t\t\t\t{product_ids[UI_TEST_TARGET]} /* {UI_TEST_TARGET}.xctest */,")
    writer.add("\t\t\t);")
    writer.add("\t\t\tname = Products;")
    writer.add("\t\t\tsourceTree = \"<group>\";")
    writer.add("\t\t};")

    main_group_id = object_id("group", "MainGroup")
    writer.add(f"\t\t{main_group_id} = {{")
    writer.add("\t\t\tisa = PBXGroup;")
    writer.add("\t\t\tchildren = (")
    writer.add(f"\t\t\t\t{config_group_id} /* Config */,")
    writer.add(f"\t\t\t\t{app_group_id} /* {APP_TARGET} */,")
    writer.add(f"\t\t\t\t{unit_group_id} /* {UNIT_TEST_TARGET} */,")
    writer.add(f"\t\t\t\t{ui_group_id} /* {UI_TEST_TARGET} */,")
    writer.add(f"\t\t\t\t{products_group_id} /* Products */,")
    writer.add("\t\t\t);")
    writer.add("\t\t\tsourceTree = \"<group>\";")
    writer.add("\t\t};")
    writer.add("/* End PBXGroup section */")

    # ------------------------------------------------------ build phases
    writer.add("")
    writer.add("/* Begin PBXFrameworksBuildPhase section */")
    for name, target_id, entries in (
        (APP_TARGET, app_target_id, [(object_id('buildFile', 'VeloCore'), "VeloCore")]),
        (UNIT_TEST_TARGET, unit_target_id,
         [(object_id('buildFile', 'VeloCoreForTests'), "VeloCore")]),
        (UI_TEST_TARGET, ui_target_id, []),
    ):
        writer.add(f"\t\t{object_id('frameworks', name)} /* Frameworks */ = {{")
        writer.add("\t\t\tisa = PBXFrameworksBuildPhase;")
        writer.add("\t\t\tbuildActionMask = 2147483647;")
        writer.add("\t\t\tfiles = (")
        for entry_id, label in entries:
            writer.add(f"\t\t\t\t{entry_id} /* {label} in Frameworks */,")
        writer.add("\t\t\t);")
        writer.add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        writer.add("\t\t};")
    writer.add("/* End PBXFrameworksBuildPhase section */")

    writer.add("")
    writer.add("/* Begin PBXSourcesBuildPhase section */")
    for name, sources in (
        (APP_TARGET, app_sources),
        (UNIT_TEST_TARGET, unit_test_sources),
        (UI_TEST_TARGET, ui_test_sources),
    ):
        writer.add(f"\t\t{object_id('sources', name)} /* Sources */ = {{")
        writer.add("\t\t\tisa = PBXSourcesBuildPhase;")
        writer.add("\t\t\tbuildActionMask = 2147483647;")
        writer.add("\t\t\tfiles = (")
        for source in sources:
            writer.add(
                f"\t\t\t\t{build_file_id(name, str(source))} /* {source.name} in Sources */,"
            )
        writer.add("\t\t\t);")
        writer.add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        writer.add("\t\t};")
    writer.add("/* End PBXSourcesBuildPhase section */")

    writer.add("")
    writer.add("/* Begin PBXResourcesBuildPhase section */")
    for name in (APP_TARGET, UNIT_TEST_TARGET, UI_TEST_TARGET):
        writer.add(f"\t\t{object_id('resources', name)} /* Resources */ = {{")
        writer.add("\t\t\tisa = PBXResourcesBuildPhase;")
        writer.add("\t\t\tbuildActionMask = 2147483647;")
        writer.add("\t\t\tfiles = (")
        if name == APP_TARGET:
            writer.add(
                f"\t\t\t\t{build_file_id(APP_TARGET, assets_relative)} "
                "/* Assets.xcassets in Resources */,"
            )
            if has_localizations:
                writer.add(
                    f"\t\t\t\t{build_file_id(APP_TARGET, 'Localizable.strings')} "
                    "/* Localizable.strings in Resources */,"
                )
        writer.add("\t\t\t);")
        writer.add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        writer.add("\t\t};")
    writer.add("/* End PBXResourcesBuildPhase section */")

    # ------------------------------------------------------- dependencies
    writer.add("")
    writer.add("/* Begin PBXTargetDependency section */")
    for name in (UNIT_TEST_TARGET, UI_TEST_TARGET):
        writer.add(f"\t\t{object_id('dependency', name)} /* PBXTargetDependency */ = {{")
        writer.add("\t\t\tisa = PBXTargetDependency;")
        writer.add(f"\t\t\ttarget = {app_target_id} /* {APP_TARGET} */;")
        writer.add(f"\t\t\ttargetProxy = {object_id('proxy', name)} /* PBXContainerItemProxy */;")
        writer.add("\t\t};")
    writer.add("/* End PBXTargetDependency section */")

    # ------------------------------------------------------------ targets
    writer.add("")
    writer.add("/* Begin PBXNativeTarget section */")
    targets = (
        (APP_TARGET, app_target_id, "com.apple.product-type.application",
         "VeloBoucle.app", [], [velo_core_product_id]),
        (UNIT_TEST_TARGET, unit_target_id, "com.apple.product-type.bundle.unit-test",
         f"{UNIT_TEST_TARGET}.xctest", [UNIT_TEST_TARGET], [velo_core_test_product_id]),
        (UI_TEST_TARGET, ui_target_id, "com.apple.product-type.bundle.ui-testing",
         f"{UI_TEST_TARGET}.xctest", [UI_TEST_TARGET], []),
    )
    for name, target_id, product_type, product_name, dependencies, package_products in targets:
        writer.add(f"\t\t{target_id} /* {name} */ = {{")
        writer.add("\t\t\tisa = PBXNativeTarget;")
        writer.add(
            f"\t\t\tbuildConfigurationList = {object_id('configList', name)} "
            f"/* Build configuration list for PBXNativeTarget \"{name}\" */;"
        )
        writer.add("\t\t\tbuildPhases = (")
        writer.add(f"\t\t\t\t{object_id('sources', name)} /* Sources */,")
        writer.add(f"\t\t\t\t{object_id('frameworks', name)} /* Frameworks */,")
        writer.add(f"\t\t\t\t{object_id('resources', name)} /* Resources */,")
        writer.add("\t\t\t);")
        writer.add("\t\t\tbuildRules = (")
        writer.add("\t\t\t);")
        writer.add("\t\t\tdependencies = (")
        for dependency in dependencies:
            writer.add(
                f"\t\t\t\t{object_id('dependency', dependency)} /* PBXTargetDependency */,"
            )
        writer.add("\t\t\t);")
        writer.add(f"\t\t\tname = {name};")
        if package_products:
            writer.add("\t\t\tpackageProductDependencies = (")
            for product in package_products:
                writer.add(f"\t\t\t\t{product} /* VeloCore */,")
            writer.add("\t\t\t);")
        writer.add(f"\t\t\tproductName = {name};")
        writer.add(f"\t\t\tproductReference = {product_ids[name]} /* {product_name} */;")
        writer.add(f"\t\t\tproductType = \"{product_type}\";")
        writer.add("\t\t};")
    writer.add("/* End PBXNativeTarget section */")

    # ------------------------------------------------------------ project
    package_reference_id = object_id("packageRef", "VeloCore")
    writer.add("")
    writer.add("/* Begin PBXProject section */")
    writer.add(f"\t\t{project_id} /* Project object */ = {{")
    writer.add("\t\t\tisa = PBXProject;")
    writer.add("\t\t\tattributes = {")
    writer.add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    writer.add("\t\t\t\tLastSwiftUpdateCheck = 1520;")
    writer.add("\t\t\t\tLastUpgradeCheck = 1520;")
    writer.add("\t\t\t\tTargetAttributes = {")
    writer.add(f"\t\t\t\t\t{app_target_id} = {{ CreatedOnToolsVersion = 15.2; }};")
    writer.add(
        f"\t\t\t\t\t{unit_target_id} = {{ CreatedOnToolsVersion = 15.2; "
        f"TestTargetID = {app_target_id}; }};"
    )
    writer.add(
        f"\t\t\t\t\t{ui_target_id} = {{ CreatedOnToolsVersion = 15.2; "
        f"TestTargetID = {app_target_id}; }};"
    )
    writer.add("\t\t\t\t};")
    writer.add("\t\t\t};")
    writer.add(
        f"\t\t\tbuildConfigurationList = {object_id('configList', 'project')} "
        "/* Build configuration list for PBXProject \"VeloBoucle\" */;"
    )
    writer.add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    writer.add("\t\t\tdevelopmentRegion = fr;")
    writer.add("\t\t\thasScannedForEncodings = 0;")
    writer.add("\t\t\tknownRegions = (")
    writer.add("\t\t\t\ten,")
    writer.add("\t\t\t\tfr,")
    writer.add("\t\t\t\tde,")
    writer.add("\t\t\t\tBase,")
    writer.add("\t\t\t);")
    writer.add(f"\t\t\tmainGroup = {main_group_id};")
    writer.add("\t\t\tpackageReferences = (")
    writer.add(f"\t\t\t\t{package_reference_id} /* XCLocalSwiftPackageReference \"../Core\" */,")
    writer.add("\t\t\t);")
    writer.add(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
    writer.add("\t\t\tprojectDirPath = \"\";")
    writer.add("\t\t\tprojectRoot = \"\";")
    writer.add("\t\t\ttargets = (")
    writer.add(f"\t\t\t\t{app_target_id} /* {APP_TARGET} */,")
    writer.add(f"\t\t\t\t{unit_target_id} /* {UNIT_TEST_TARGET} */,")
    writer.add(f"\t\t\t\t{ui_target_id} /* {UI_TEST_TARGET} */,")
    writer.add("\t\t\t);")
    writer.add("\t\t};")
    writer.add("/* End PBXProject section */")

    # ------------------------------------------------------------ packages
    writer.add("")
    writer.add("/* Begin XCLocalSwiftPackageReference section */")
    writer.add(
        f"\t\t{package_reference_id} /* XCLocalSwiftPackageReference \"../Core\" */ = {{"
    )
    writer.add("\t\t\tisa = XCLocalSwiftPackageReference;")
    writer.add("\t\t\trelativePath = ../Core;")
    writer.add("\t\t};")
    writer.add("/* End XCLocalSwiftPackageReference section */")

    writer.add("")
    writer.add("/* Begin XCSwiftPackageProductDependency section */")
    for product_id in (velo_core_product_id, velo_core_test_product_id):
        writer.add(f"\t\t{product_id} /* VeloCore */ = {{")
        writer.add("\t\t\tisa = XCSwiftPackageProductDependency;")
        writer.add("\t\t\tproductName = VeloCore;")
        writer.add("\t\t};")
    writer.add("/* End XCSwiftPackageProductDependency section */")

    # ------------------------------------------------------ configurations
    writer.add("")
    writer.add("/* Begin XCBuildConfiguration section */")

    def emit_configuration(scope: str, configuration: str, settings: dict[str, str]) -> None:
        writer.add(
            f"\t\t{object_id('buildConfig', scope, configuration)} /* {configuration} */ = {{"
        )
        writer.add("\t\t\tisa = XCBuildConfiguration;")
        writer.add(
            f"\t\t\tbaseConfigurationReference = {object_id('config', configuration)} "
            f"/* {configuration}.xcconfig */;"
        )
        writer.add("\t\t\tbuildSettings = {")
        for key in sorted(settings):
            writer.add(f"\t\t\t\t{key} = {settings[key]};")
        writer.add("\t\t\t};")
        writer.add(f"\t\t\tname = {configuration};")
        writer.add("\t\t};")

    project_settings = {
        "SDKROOT": "iphoneos",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "NO",
    }
    app_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "\"\"",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{APP_TARGET}/Resources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "\"$(inherited) @executable_path/Frameworks\"",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    unit_settings = {
        "BUNDLE_LOADER": "\"$(TEST_HOST)\"",
        "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
        "TEST_HOST": (
            f"\"$(BUILT_PRODUCTS_DIR)/{APP_TARGET}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)"
            f"/{APP_TARGET}\""
        ),
    }
    ui_settings = {
        "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.uitests",
        "TEST_TARGET_NAME": APP_TARGET,
    }

    for configuration in ("Debug", "Release"):
        emit_configuration("project", configuration, project_settings)
        emit_configuration(APP_TARGET, configuration, app_settings)
        emit_configuration(UNIT_TEST_TARGET, configuration, unit_settings)
        emit_configuration(UI_TEST_TARGET, configuration, ui_settings)
    writer.add("/* End XCBuildConfiguration section */")

    writer.add("")
    writer.add("/* Begin XCConfigurationList section */")
    for scope, label in (
        ("project", "PBXProject \"VeloBoucle\""),
        (APP_TARGET, f"PBXNativeTarget \"{APP_TARGET}\""),
        (UNIT_TEST_TARGET, f"PBXNativeTarget \"{UNIT_TEST_TARGET}\""),
        (UI_TEST_TARGET, f"PBXNativeTarget \"{UI_TEST_TARGET}\""),
    ):
        writer.add(
            f"\t\t{object_id('configList', scope)} /* Build configuration list for {label} */ = {{"
        )
        writer.add("\t\t\tisa = XCConfigurationList;")
        writer.add("\t\t\tbuildConfigurations = (")
        for configuration in ("Debug", "Release"):
            writer.add(
                f"\t\t\t\t{object_id('buildConfig', scope, configuration)} /* {configuration} */,"
            )
        writer.add("\t\t\t);")
        writer.add("\t\t\tdefaultConfigurationIsVisible = 0;")
        writer.add("\t\t\tdefaultConfigurationName = Release;")
        writer.add("\t\t};")
    writer.add("/* End XCConfigurationList section */")

    writer.add("\t};")
    writer.add(f"\trootObject = {project_id} /* Project object */;")
    writer.add("}")

    # ---------------------------------------------------------- écriture
    if PROJECT_PATH.exists():
        shutil.rmtree(PROJECT_PATH)
    PROJECT_PATH.mkdir(parents=True)
    (PROJECT_PATH / "project.pbxproj").write_text(writer.render(), encoding="utf-8")

    write_scheme()
    write_workspace_settings()

    print(f"Projet généré : {PROJECT_PATH.relative_to(REPO_ROOT)}")
    print(f"  {len(app_sources)} sources d'application")
    print(f"  {len(unit_test_sources)} sources de tests unitaires")
    print(f"  {len(ui_test_sources)} sources de tests d'interface")
    return 0


def write_workspace_settings() -> None:
    workspace = PROJECT_PATH / "project.xcworkspace"
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Workspace version="1.0">\n'
        '   <FileRef location="self:">\n'
        "   </FileRef>\n"
        "</Workspace>\n",
        encoding="utf-8",
    )


def write_scheme() -> None:
    """Schéma partagé, indispensable pour `xcodebuild -scheme VeloBoucle`."""
    schemes = PROJECT_PATH / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)

    app_target_id = object_id("target", APP_TARGET)
    unit_target_id = object_id("target", UNIT_TEST_TARGET)
    ui_target_id = object_id("target", UI_TEST_TARGET)

    def reference(target_id: str, name: str, product: str) -> str:
        return (
            "<BuildableReference\n"
            '                  BuildableIdentifier = "primary"\n'
            f'                  BlueprintIdentifier = "{target_id}"\n'
            f'                  BuildableName = "{product}"\n'
            f'                  BlueprintName = "{name}"\n'
            '                  ReferencedContainer = "container:VeloBoucle.xcodeproj">\n'
            "               </BuildableReference>"
        )

    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1520" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES"
            buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target_id}"
               BuildableName = "VeloBoucle.app"
               BlueprintName = "{APP_TARGET}"
               ReferencedContainer = "container:VeloBoucle.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{unit_target_id}"
               BuildableName = "{UNIT_TEST_TARGET}.xctest"
               BlueprintName = "{UNIT_TEST_TARGET}"
               ReferencedContainer = "container:VeloBoucle.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ui_target_id}"
               BuildableName = "{UI_TEST_TARGET}.xctest"
               BlueprintName = "{UI_TEST_TARGET}"
               ReferencedContainer = "container:VeloBoucle.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES" debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "VeloBoucle.app"
            BlueprintName = "{APP_TARGET}"
            ReferencedContainer = "container:VeloBoucle.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "VeloBoucle.app"
            BlueprintName = "{APP_TARGET}"
            ReferencedContainer = "container:VeloBoucle.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""
    _ = reference  # conservé pour lisibilité de la structure
    (schemes / f"{APP_TARGET}.xcscheme").write_text(scheme, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
