import { createIcons, LocateFixed, Map, Maximize, MousePointer2, Sparkles, Volume2, VolumeX, X, ZoomIn, ZoomOut } from "lucide";

const icons = { LocateFixed, Map, Maximize, MousePointer2, Sparkles, Volume2, VolumeX, X, ZoomIn, ZoomOut };

export function renderTrainingGameIcons(root = document) {
  createIcons({ icons, attrs: { "aria-hidden": "true" }, nameAttr: "data-lucide", root });
}
