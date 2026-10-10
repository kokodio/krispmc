package com.krispmc;

import net.fabricmc.loader.api.FabricLoader;
import net.fabricmc.loader.api.entrypoint.PreLaunchEntrypoint;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.invoke.MethodHandle;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_INT;

public class KrispMC implements PreLaunchEntrypoint {

    public static final String MOD_ID = "krispmc";
    public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);
    private static final String RESOURCE_DIR = "natives/macos-arm64/";
    private static final String LOADER = "libvulkan.1.dylib";
    private static final String DRIVER = "libvulkan_kosmickrisp.dylib";
    private static final String ICD_MANIFEST = """
            {
                "file_format_version": "1.0.0",
                "ICD": {
                    "library_path": "%s",
                    "api_version": "1.4.0"
                }
            }
            """;
    private static final Linker LINKER = Linker.nativeLinker();
    private static final MethodHandle SETENV = LINKER.downcallHandle(
            LINKER.defaultLookup().find("setenv").orElseThrow(),
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS, JAVA_INT));

    private static Path extract(Path dir, String name) throws IOException {
        Path source = FabricLoader.getInstance().getModContainer(MOD_ID).orElseThrow()
                .findPath(RESOURCE_DIR + name).orElseThrow(() -> new IOException("Missing bundled library " + name));
        Path target = dir.resolve(name);

        if (!Files.exists(target) || Files.mismatch(source, target) != -1) {
            Files.copy(source, target, StandardCopyOption.REPLACE_EXISTING);
        }
        return target;
    }

    @Override
    public void onPreLaunch() {
        try {
            Path dir = Files.createDirectories(FabricLoader.getInstance().getGameDir().toAbsolutePath().resolve("krispmc"));
            Path loader = extract(dir, LOADER);
            Path driver = extract(dir, DRIVER);

            String path = driver.toString().replace("\\", "\\\\").replace("\"", "\\\"");
            Path manifest = Files.writeString(dir.resolve("kosmickrisp_icd.json"), ICD_MANIFEST.formatted(path));

            try (Arena arena = Arena.ofConfined()) {
                int result = (int) SETENV.invokeExact(arena.allocateFrom("VK_DRIVER_FILES"), arena.allocateFrom(manifest.toString()), 1);
                if (result != 0) {
                    throw new IllegalStateException("setenv failed with " + result);
                }
            }

            System.setProperty("org.lwjgl.vulkan.libname", loader.toString());

            LOGGER.info("Using the KosmicKrisp Vulkan driver from {}", dir);
        } catch (Throwable t) {
            LOGGER.error("Failed to set up KosmicKrisp, falling back to MoltenVK", t);
        }
    }
}
