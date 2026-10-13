# ClassMacros

Macros for every class in WoW: Forever. They are kept as plain `.macro` files and compiled into an addon. When you log in, the addon creates or updates the macros for your character's class in your per-character macro slots.

## Layout

```
macros/<class>/*.macro   source macros, one file per macro
addon/ClassMacros/       addon source (Core.lua, .toc template)
tools/build.py           lints macros and builds the addon into dist/
```

## Writing macros

- The macro name comes from the filename: `mortal-strike.macro` becomes `Mortal Strike`.
- Names longer than 16 characters need a `#name <Short Name>` first line. The build strips this line from the body.
- A macro body can be at most 255 characters, and a class can have at most 18 macros (the per-character limit).
- `<Key>` is a per-character placeholder, such as `<Shield>` in `macros/warrior/gear.macro`. Set it in game with `/cm set "Shield" Aegis of Stormwind`. A macro with unset placeholders is skipped until you fill them.

## Building and installing

```sh
python3 tools/build.py                                        # lint + build dist/ClassMacros
python3 tools/build.py --install "/path/to/WoW/Interface/AddOns"
python3 tools/build.py --zip                                  # dist/ClassMacros.zip
python3 tools/build.py --interface 11200                      # set the .toc Interface number
```

If the client lists the addon as out of date, find your Interface number in game and rebuild with `--interface`. If the first command errors on your client, use the second:

```
/run print(select(4, GetBuildInfo()))
/run DEFAULT_CHAT_FRAME:AddMessage(GetBuildInfo())
```

## In game

| Command | What it does |
| --- | --- |
| `/cm sync` | Sync macros now (also runs on login, and after combat if you logged in mid-fight) |
| `/cm list` | Show each macro for your class and its sync status |
| `/cm get` | Show placeholder values for this character |
| `/cm set "<Key>" <value>` | Set a placeholder (empty value clears it) |
| `/cm reset` | Delete every macro the addon manages |

The addon only edits per-character macros with the same name as one of its macros. It never touches account-wide macros: if an account-wide macro already uses the name, that macro is skipped. When you edit a macro and rebuild, the macro is updated in place, so it stays on your action bars. If you delete a `.macro` file, the addon deletes the macro it created from that file.

## License

[MIT](LICENSE)
