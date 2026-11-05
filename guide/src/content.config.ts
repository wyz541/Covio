import { defineCollection } from 'astro:content';
import { docsLoader, i18nLoader } from '@astrojs/starlight/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';
import { z } from 'astro/zod';

const capabilitySchema = z.object({
  id: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
  title: z.string().min(1),
  description: z.string().min(1),
});

const implementationSchema = z.object({
  swift: z.array(z.string().min(1)).default([]),
  notes: z.string().min(1).optional(),
});

const evidenceSchema = ({ image }: { image: () => z.ZodType }) =>
  z.object({
    id: z.string().min(1),
    image: image(),
    alt: z.string().min(1),
    capturedAt: z.coerce.date(),
    device: z.string().min(1),
    os: z.string().min(1),
    appearance: z.enum(['light', 'dark']).optional(),
    scene: z.string().min(1),
    sourceCommit: z.string().regex(/^[0-9a-f]{7,40}$/),
    sourceBranch: z.string().min(1).optional(),
    sha256: z.string().regex(/^[0-9a-f]{64}$/),
    status: z.enum(['real-device', 'preview-placeholder']),
    maxWidth: z.number().positive().optional(),
  });

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({
      extend: ({ image }) =>
        z.object({
          component: z
            .object({
              id: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
              kind: z.enum([
                'shell',
                'surface',
                'navigation',
                'control',
                'container',
                'feedback',
                'indicator',
                'menu',
                'content',
                'decoration',
              ]),
              status: z.enum(['draft', 'preview', 'stable', 'deprecated']),
              definition: z.string().min(1),
              capabilities: z.array(capabilitySchema).min(1),
              states: z.array(z.string().min(1)).min(1),
              platforms: z.array(z.string().min(1)).min(1),
              accessibilityRules: z.array(z.string().min(1)).default([]),
              implementation: implementationSchema.optional(),
              related: z.array(z.string().min(1)).default([]),
            })
            .optional(),
          evidence: z.array(evidenceSchema({ image })).default([]),
        }),
    }),
  }),
  i18n: defineCollection({ loader: i18nLoader(), schema: i18nSchema() }),
};
