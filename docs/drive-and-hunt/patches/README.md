# Drive-and-Hunt changes not in the commit

These nine files carry Drive-and-Hunt edits on top of owner work that is not committed yet, so they
could not be committed without also committing that work. Each patch is the Drive-and-Hunt change
only (pre-work snapshot → current file). The working tree already contains them; the patches are a
record, not something to apply.

Tracked, with other uncommitted owner changes: `SleepLauncherController.client.lua`,
`Bootstrap.server.lua`, `CartOccupantService.lua`, `CartService.lua`, `RemoteNames.lua`.

Never committed (owner files): `BrainrotInteractionSystem.lua`, `DriveByHaulSystem.lua`,
`CartResetExecutor.lua`, `CartInputRegistry.lua`.

Until these files are committed, the committed tree does not run Drive-and-Hunt on its own.
