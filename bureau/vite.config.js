import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// Chemins relatifs : la page marche aussi bien en local que sous /bim/bureau/.
export default defineConfig({ base: './', plugins: [svelte()] });
