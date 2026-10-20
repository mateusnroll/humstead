# Humstead — starter audio research

Researched September 20, 2026. Initial candidate research; see the acquisition update below. No playback audition, audio editing or shipping approval. Station placements are tentative inferences from creator descriptions/tags, not listening judgments. The shortlist supplies nine named music candidates and four ambience candidates; actual sound quality and usable loop boundaries remain to be verified.

## Music shortlist

| Tentative station | Original track/source | Creator | Published license | Published duration | Evidence and caveat |
| --- | --- | --- | --- | --- | --- |
| Mellow | [Morning Coffee](https://freemusicarchive.org/music/holiznacc0/lo-fi-and-chill/morning-coffee/) | HoliznaCC0 | CC0 1.0 | 03:11 | Indexed individual FMA page explicitly states CC0; direct FMA fetching unreliable. |
| Mellow | [lofi hip hop](https://opengameart.org/content/lofi-hip-hop) | omfgdude | CC0 | not measured | Individual page read; author mentions prerecorded loops and Yamaha Motif, so preserve provenance and inspect source-component rights before bundling. |
| Mellow | [Lofi again](https://opengameart.org/content/lofi-again) | omfgdude | CC0 | not measured | Individual page read; description mentions baked-in ambience, which may limit a genuinely music-only mix. |
| Jazzy | [Keeping Cool](https://freemusicarchive.org/music/holiznacc0/busted-guitar-lofi-edit/keeping-cool/) | HoliznaCC0 | CC0 1.0 | 02:33 | Indexed individual page states CC0 and jazz/lofi genres. |
| Jazzy | [Funky Hip Hop Lofi Jam](https://opengameart.org/content/funky-hip-hop-lofi-jam) | omfgdude | CC0 | not measured | Individual page read; choose one of original/lowpass versions. Yamaha styles mentioned; verify source-component rights before bundling. |
| Jazzy | [Chills](https://opengameart.org/content/chills) | Holizna | CC0 | not measured | Individual page read; sax/noir/lofi tags suggest this placement. |
| Late Night | [Not It (Lofi).mp3](https://freemusicarchive.org/index.php/music/holiznacc0/lo-fi-and-chill/not-it-lofimp3/) | HoliznaCC0 | CC0 1.0 | 02:57 | Indexed individual page explicitly states CC0; placement requires audition. |
| Late Night | [The Past (8 Bit Lofi Hip Hop)](https://opengameart.org/content/the-past-8-bit-lofi-hip-hop) | TAD | CC0 and CC BY 4.0 offered | not measured | Individual page read; 8-bit character may differ from desired station tone. Elect one offered license when packaging. |
| Late Night | [Ooame](https://opengameart.org/content/ooame) | TAD | CC0 and CC BY 4.0 offered | not measured | Individual page read; sad piano/chiptune tags. Elect one offered license when packaging. |

Creator destinations to retain alongside each original track link:
- [HoliznaCC0 artist page](https://holiznacc0.bandcamp.com/): the artist describes the CC0 dedication. Do not assume every separate paid/Patreon release has the same terms.
- [omfgdude profile](https://opengameart.org/users/omfgdude).
- [TAD channel](https://www.youtube.com/c/Tadon), explicitly supplied on both track pages.

## Ambience shortlist

All four individual Freesound pages explicitly display Creative Commons 0. Original downloads require a Freesound login; no login was attempted or bypassed. Sizes below are source-page figures, not verified downloaded sizes.

| Layer | Original recording/source | Creator/profile | Duration | Size | Audition note |
| --- | --- | --- | --- | --- | --- |
| Rain | [Rain_01.wav](https://freesound.org/people/Q.K./sounds/56306/) | [Q.K.](https://freesound.org/people/Q.K./) | 25.761 s | 4.3 MB | Light rainfall; inspect loop seam. |
| Café | [QUIET CAFE, CHATTER, MILK FROTHING MACHINE, atmos atmosphere wildtrack ambience.mp3](https://freesound.org/people/Anya_Media/sounds/437461/) | [Anya_Media](https://freesound.org/people/Anya_Media/) | 120.685 s | 4.6 MB | Former URL uses arpeggio1980; current source credits Anya_Media. Audition for intelligible speech/background music and edit around disruptive milk frother. |
| Fireplace | [Fire Crackle with Roaring Chimney](https://freesound.org/people/TheWoodlandNomad/sounds/363091/) | [TheWoodlandNomad](https://freesound.org/people/TheWoodlandNomad/) | 30.901 s | 5.2 MB | Described as gentle living-room log fire with chimney roar; inspect sharp transients and loop seam. |
| Forest | [Forest Ambience 3](https://freesound.org/people/deadrobotmusic/sounds/687069/) | [deadrobotmusic](https://freesound.org/people/deadrobotmusic/) | 36.251 s | 12.2 MB | Stereo WAV; inspect repetition, noise and isolated foreground events. |

## Alternative pool

[Holizna's Lo-Fi and Chill collection on OpenGameArt](https://opengameart.org/node/161819) explicitly offers CC0 archives. [The artist's Bandcamp album](https://holiznacc0.bandcamp.com/album/lofi-and-chill) describes its public-domain dedication and lists individual songs. This is the preferred pool if the omfgdude source-loop provenance or TAD chiptune tone is unsuitable. Examples to investigate further: Everything You Ever Dreamed, A Little Shade, Foggy Headed. Individual FMA pages for these could not be fetched reliably during this pass, so they are not asserted as individually checked candidates here.

## Before packaging

Acquire originals through authorized download routes; preserve asset-specific license evidence/date, original filenames and SHA256. Verify source-component rights where loops/styles are mentioned; CC0 metadata alone is not proof of third-party clearance. Audition music for station fit, distracting vocals/baked ambience, clipping and disruptive intros/outros. Audition café for identifiable speech or third-party background music. Prepare seamless ambience edits only after acceptance, recording transformations. Preserve artist profiles and original source links even where CC0 does not require attribution.

Later manually curated catalog expansion is intended; this does not add an in-app upload/import feature to v1. No tracks are declared final or bundled by this research.

## Acquisition update — September 21, 2026

User approved obtaining originals and account creation. Eight selected songs are downloaded: lofi hip hop, Lofi again, Funky Hip Hop Lofi Jam (original version), Chills, The Past, Ooame, Keeping Cool and Morning Coffee. The last two came from Holizna’s CC0 OpenGameArt collection. TAD tracks use the offered CC0 license, with credits retained. Original files, license-page evidence, artist URLs, SHA-256 hashes and afinfo metadata are retained in the Liftoff run’s `audio-sources/` directory, outside the future repository. All eight were recognized by macOS afinfo; this is metadata verification, not listening or app compatibility testing.

Not It (Lofi) and the four ambience originals remain pending login. No accounts were created. Freesound registration requires password entry, CAPTCHA and terms; browser policy requires a user handoff, and the user currently has only remote access. FMA also requires login. HEY authentication is working. No passwords, account tokens or verification links were saved. The three public Holizna collection ZIPs are preserved as acquisition evidence and are not proposed bundle contents.

## Additional music acquired — September 21, 2026

Four further CC0 candidates extracted unchanged from the already-downloaded Holizna OpenGameArt collection: Everything You Ever Dreamed (3:40), A Little Shade (2:59), Creature Comforts (2:55), and Foggy Headed (4:06). This adds 32.8 MB and about 13.7 minutes, bringing the available pool to 12 distinct songs. The publisher’s collection page explicitly offers CC0 and public downloads without login. `audio-sources/additional-music-manifest.json` preserves archive members, original filenames, license evidence, source/profile links, SHA-256 and afinfo results. All four metadata reads succeeded; no audition or shipping approval is implied. Creature Comforts is an available candidate to audition instead of the login-blocked Not It; station placement remains undecided. The four ambience originals remain pending.

## Account-free ambience replacements — September 21, 2026

All four files acquired unchanged, published under CC0 1.0; evidence, creator profiles, hashes and successful afinfo metadata results are retained in the run’s `audio-sources/ambience/manifest.json`. These replace the account dependency for evaluation, not a claim that they have passed audition or been approved for shipping.

| Layer | Recording / source | Creator | Measured duration | Source size |
| --- | --- | --- | --- | --- |
| Rain | [Rain in the Gutter Loop](https://opengameart.org/content/rain-gutter-loop) | [Ogrebane](https://opengameart.org/users/ogrebane) | 61.60 s | 1.48 MB |
| Fireplace | [Fireplace Sound loop](https://opengameart.org/content/fireplace-sound-loop) | [PagDev](https://opengameart.org/users/pagdev) | 29.26 s | 10.32 MB |
| Forest | [Park ambiences — birds](https://opengameart.org/content/park-ambiences) | [Thimras](https://opengameart.org/users/thimras) | 448.90 s | 86.19 MB |
| Cafe | [Coffee Shop at the Capucins](https://bigsoundbank.com/coffee-shop-at-the-capucins-s2561.html) | [Joseph SARDIN](https://josephsardin.fr/) | 242.83 s | 5.83 MB |

Rain and fireplace are described by their authors as loops; seams are not yet verified. Forest uses the birds-near-trees recording from a public park in Adelaide, rather than a remote forest recording. Café needs a speech/background-music check; its public MP3 was acquired rather than a WAV master. The large source forest WAV is retained for editing, not a proposed shipped size. Preserve original files; record later cuts, fades, normalization and encoding separately.

Other sources considered: the Signature Sounds café pack is CC0 but its MediaFire link was blocked by the browser, so it was not used. Wikimedia’s Cafe ambiance file has an unresolved provenance question on its talk page, so it was not selected. No signup, security-setting changes, or authentication bypass were used.
