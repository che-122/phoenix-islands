<script lang="ts">
  import { onMount } from "svelte";
  import { fromStore } from "svelte/store";
  import { playerStore, formatTime, isPlayableAttachment } from "../player_store";

  let audio = $state<HTMLAudioElement | null>(null);
  let lastHandledCommandId = -1;
  let loadedMediaId = $state<string | null>(null);

  const player = fromStore(playerStore);

  let seekValue = $state<[number]>([0]);
  let volumeValue = $state<[number]>([1]);
  const currentSources = $derived(
    (player.current.current?.attachments ?? []).filter((attachment) => isPlayableAttachment(attachment)),
  );

  function syncFromAudio() {
    if (!audio) return;

    playerStore.setProgress(audio.currentTime, audio.duration || 0);
    playerStore.setVolumeState(audio.volume, audio.muted);

    seekValue[0] = audio.currentTime;
    volumeValue[0] = audio.muted ? 0 : audio.volume;
  }

  async function loadAndPlay() {
    if (!audio || !player.current.current) return;
    if (currentSources.length === 0) {
      playerStore.setError("No playable media found");
      return;
    }

    playerStore.setLoading();
    loadedMediaId = player.current.current.id;

    try {
      audio.pause();
      audio.currentTime = 0;
      audio.load();
      await audio.play();
      playerStore.setPlaying();
    } catch (err) {
      playerStore.setError(
        err instanceof Error ? err.message : "Playback failed",
      );
    }
  }

  async function handleCommand() {
    const command = player.current.lastCommand;
    if (!audio || !command) return;
    if (command.id === lastHandledCommandId) return;

    lastHandledCommandId = command.id;

    switch (command.type) {
      case "play": {
        await loadAndPlay();
        break;
      }

      case "pause": {
        audio.pause();
        break;
      }

      case "toggle": {
        const requestedMedia = command.media;

        if (requestedMedia && loadedMediaId !== requestedMedia.id) {
          playerStore.requestPlay(requestedMedia);
          return;
        }

        if (audio.paused) {
          try {
            await audio.play();
            playerStore.setPlaying();
          } catch (err) {
            playerStore.setError(
              err instanceof Error ? err.message : "Playback failed",
            );
          }
        } else {
          audio.pause();
        }
        break;
      }

      case "seek": {
        audio.currentTime = command.time;
        syncFromAudio();
        break;
      }

      case "setVolume": {
        audio.volume = command.volume;
        audio.muted = command.volume === 0;
        syncFromAudio();
        break;
      }

      case "toggleMute": {
        audio.muted = !audio.muted;
        syncFromAudio();
        break;
      }
    }
  }

  function onLoadedMetadata() {
    if (!audio) return;
    playerStore.setDuration(audio.duration || 0);
    syncFromAudio();
  }

  function onLoadStart() {
    if (player.current.status !== "playing") {
      playerStore.setLoading();
    }
  }

  function onPlay() {
    playerStore.setPlaying();
  }

  function onPause() {
    playerStore.setPaused();
  }

  function onTimeUpdate() {
    syncFromAudio();
  }

  function onVolumeChange() {
    syncFromAudio();
  }

  function onEnded() {
    playerStore.setPaused();
    if (audio) {
      audio.currentTime = 0;
      syncFromAudio();
    }
  }

  function onError() {
    const media = player.current.current;
    playerStore.setError(
      media ? `Audio failed to load for ${media.title}` : "Audio failed to load",
    );
  }

  function onSeekInput(value: number[]) {
    const time = value[0] ?? 0;
    playerStore.requestSeek(time);
  }

  function onVolumeInput(value: number[]) {
    const volume = value[0] ?? 0;
    playerStore.requestSetVolume(volume);
  }

  $effect(() => {
    handleCommand();
  });

  onMount(() => {
    return () => {
      audio?.pause();
    };
  });
</script>

{#if player.current.current}
  <audio
    bind:this={audio}
    onloadedmetadata={onLoadedMetadata}
    onloadstart={onLoadStart}
    onplay={onPlay}
    onpause={onPause}
    ontimeupdate={onTimeUpdate}
    onvolumechange={onVolumeChange}
    onended={onEnded}
    onerror={onError}
  >
    {#each currentSources as attachment}
      <source src={attachment.url} type={attachment.mimeType} />
    {/each}
  </audio>

  <div class="border-b border-base-300 bg-base-100 px-4 py-3 shadow-sm sm:px-6">
    <div class="mx-auto flex w-full max-w-[120rem] flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
      <div class="min-w-0">
        <p class="truncate text-sm font-semibold text-base-content">{player.current.current.title}</p>
        <p class="truncate text-xs text-base-content/70">{player.current.current.feedTitle}</p>
        {#if player.current.error}
          <p class="mt-1 text-xs text-error">{player.current.error}</p>
        {/if}
      </div>

      <div class="flex items-center gap-2">
        <button
          type="button"
          class="rounded-lg border border-base-300 px-3 py-1.5 text-sm font-medium text-base-content transition-colors hover:bg-base-200"
          onclick={() =>
            player.current.status === "playing"
              ? playerStore.requestPause()
              : playerStore.requestToggle()}
        >
          {#if player.current.status === "playing"}
            Pause
          {:else}
            Play
          {/if}
        </button>

        <button
          type="button"
          class="rounded-lg border border-base-300 px-3 py-1.5 text-xs font-medium text-base-content/80 transition-colors hover:bg-base-200"
          onclick={() => playerStore.requestToggleMute()}
        >
          {player.current.muted ? "Unmute" : "Mute"}
        </button>
      </div>

      <div class="grid grid-cols-1 gap-2 lg:w-[36rem]">
        <div class="flex items-center gap-2">
          <input
            type="range"
            class="range range-xs w-full"
            min="0"
            max={player.current.duration || 0}
            step="0.1"
            value={seekValue[0]}
            oninput={(e) =>
              onSeekInput([Number((e.currentTarget as HTMLInputElement).value)])}
          />
          <span class="w-28 text-right text-xs text-base-content/70">
            {formatTime(player.current.currentTime)} / {formatTime(
              player.current.duration,
            )}
          </span>
        </div>

        <div class="flex items-center gap-2">
          <span class="w-10 text-xs text-base-content/60">Vol</span>
          <input
            type="range"
            class="range range-xs w-full"
            min="0"
            max="1"
            step="0.01"
            value={volumeValue[0]}
            oninput={(e) =>
              onVolumeInput([Number((e.currentTarget as HTMLInputElement).value)])}
          />
        </div>
      </div>
    </div>
  </div>
{/if}
