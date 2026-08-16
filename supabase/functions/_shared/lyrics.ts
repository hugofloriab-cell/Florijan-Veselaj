// Représentation des paroles, partagée par les fonctions qui alimentent le
// moteur audio. Miroir de la colonne lyrics_documents.content.

export interface LyricsLine {
  text: string;
  syllables?: number;
}

export interface LyricsSection {
  type: string;
  index?: number;
  lines: LyricsLine[];
}

/**
 * Aplatit le document structuré en texte à marqueurs de section, format attendu
 * par les moteurs de génération musicale.
 */
export function flattenLyrics(sections: LyricsSection[]): string {
  return sections
    .map((section) => {
      const heading = section.index
        ? `[${section.type} ${section.index}]`
        : `[${section.type}]`;
      return [heading, ...section.lines.map((line) => line.text)].join("\n");
    })
    .join("\n\n");
}
