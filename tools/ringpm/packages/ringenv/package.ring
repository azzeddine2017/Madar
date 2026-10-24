

aPackageInfo = [
	:name = "ringenv",
	:description = "Isolated Virtual Environment and Version Manager for Ring Programming Language",
	:folder = "ringenv",
	:developer = "Azzeddine Remmal",
	:email = "azzeddine.remmal@gmail.com",
	:license = "MIT License",
	:version = "1.1.1",
	:ringversion = "1.27",
	:versions = [
		[
			:version = "1.1.1",
			:branch = "master"
		],
		[
			:version = "1.0.3",
			:branch = "master"
		]
	],
	:libs = [
		[
			:name = "stdlib",
			:version = "1.0",
			:providerusername = ""
		]
	],
	:files = [
		"main.ring",
		"setup.ring",
		"README.md",
		"package.ring",
		"src/core/ui_style.ring",
		"src/core/os_helper.ring",
		"src/core/categories.ring",
		"src/core/zipengine.ring",
		"src/core/downloader.ring",
		"src/core/extractor.ring",
		"src/commands/cmd_install.ring",
		"src/commands/cmd_remove.ring",
		"src/commands/cmd_list.ring",
		"src/commands/cmd_list_remote.ring",
		"src/commands/cmd_hub.ring",
		"src/commands/cmd_venv.ring",
		"src/commands/cmd_build.ring",
		"src/commands/cmd_harvest.ring",
		"tests/ringenv_test.ring",
		"docs/README.md",
		"docs/getting_started.md",
		"docs/version_management.md",
		"docs/virtual_environments.md",
		"docs/community_hub.md",
		"docs/packaging_and_distribution.md"
	],
	:ringfolderfiles = [

	],
	:windowsfiles = [

	],
	:linuxfiles = [

	],
	:macosfiles = [

	],
	:windowsringfolderfiles = [

	],
	:linuxringfolderfiles = [

	],
	:macosringfolderfiles = [

	],
	:run = "ring main.ring",
	:setup = "ring setup.ring",
	:windowssetup = "",
	:linuxsetup = "",
	:macossetup = "",
	:ubuntusetup = "",
	:fedorasetup = "",
	:remove = "ring setup.ring remove",
	:windowsremove = "",
	:linuxremove = "",
	:macosremove = "",
	:ubunturemove = "",
	:fedoraremove = "",
	:remotefolder = "ringenv",
	:branch = "master",
	:providerusername = "",
	:providerwebsite = "github.com"
]
