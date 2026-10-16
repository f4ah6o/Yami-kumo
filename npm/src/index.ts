import { render } from './moonbit.js';

declare const htmlBrand: unique symbol;
export interface Html {
  readonly [htmlBrand]: true;
}
export type Child = Html | string;
export type Children = Child | readonly Child[];
export type Attributes = Readonly<Record<string, string | boolean>>;
export type ControlSize = 'xs' | 'sm' | 'base' | 'lg';
export type ButtonVariant =
  | 'primary'
  | 'secondary'
  | 'ghost'
  | 'destructive'
  | 'secondary-destructive'
  | 'outline';
export type TextVariant =
  | 'heading'
  | 'body'
  | 'secondary'
  | 'success'
  | 'error'
  | 'mono'
  | 'mono-secondary';
export interface CommonProps {
  className?: string;
  attrs?: Attributes;
}
export interface ButtonProps extends CommonProps {
  variant?: ButtonVariant;
  size?: ControlSize;
  disabled?: boolean;
  type?: 'button' | 'submit' | 'reset';
}
export interface InputProps extends CommonProps {
  id: string;
  size?: ControlSize;
  variant?: 'default' | 'error';
  label?: Child;
  description?: Child;
  error?: Child;
  placeholder?: string;
  disabled?: boolean;
  required?: boolean;
}
export interface TextProps extends CommonProps {
  variant?: TextVariant;
  size?: ControlSize;
  as?: string;
  bold?: boolean;
  truncate?: boolean;
}
export interface LayerCardProps extends CommonProps {
  layered?: boolean;
}
export interface AppShellProps {
  brand: Child;
  children: Children;
  navigationTrigger?: Child;
  globalSearch?: Child;
  headerActions?: Child;
  accountMenu?: Child;
  rail?: Child;
  sidebar?: Child;
  tabs?: Child;
  contextPanel?: Child;
  bottomBar?: Child;
  contextPanelLabel?: string;
  closeContextPanelLabel?: string;
  primaryNavigationLabel?: string;
  workspaceNavigationLabel?: string;
  closeWorkspaceNavigationLabel?: string;
  sidebarCollapsed?: boolean;
  mobileSidebarOpen?: boolean;
  contextPanelOpen?: boolean;
}

interface Spec {
  kind: string;
  props?: Record<string, unknown>;
  children?: Spec[];
  value?: string;
}
const nodes = new WeakMap<object, Spec>();
type Rule = 'string' | 'boolean' | 'child' | 'attrs' | readonly string[];
const common = { className: 'string', attrs: 'attrs' } as const;
const sizes = ['xs', 'sm', 'base', 'lg'] as const;

function node(spec: Spec): Html {
  const handle = Object.freeze({}) as Html;
  nodes.set(handle, spec);
  return handle;
}
function child(value: Child): Spec {
  if (typeof value === 'string') return { kind: 'text', value };
  const spec = value && typeof value === 'object' ? nodes.get(value) : undefined;
  if (!spec) throw new TypeError('Expected a string or a Yami-kumo Html node');
  return spec;
}
function children(values: Children): Spec[] {
  return (Array.isArray(values) ? values : [values]).map(child);
}
function props(value: unknown, rules: Record<string, Rule>): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new TypeError('Expected props object');
  const result: Record<string, unknown> = {};
  for (const [key, val] of Object.entries(value)) {
    const rule = Object.hasOwn(rules, key) ? rules[key] : undefined;
    if (!rule) throw new TypeError(`Unsupported prop: ${key}`);
    if (val === undefined) continue;
    if (rule === 'child') result[key] = child(val as Child);
    else if (rule === 'attrs') {
      if (!val || typeof val !== 'object' || Array.isArray(val))
        throw new TypeError('Expected attrs object');
      const entries = Object.entries(val);
      if (entries.some(([, v]) => typeof v !== 'string' && typeof v !== 'boolean'))
        throw new TypeError('Attribute values must be strings or booleans');
      result[key] = Object.fromEntries(entries);
    } else if (typeof rule === 'string') {
      if (typeof val !== rule) throw new TypeError(`Expected ${key} to be ${rule}`);
      result[key] = val;
    } else {
      if (typeof val !== 'string' || !rule.includes(val))
        throw new TypeError(`Unsupported ${key}: ${String(val)}`);
      result[key] = val;
    }
  }
  return result;
}
export function text(value: string): Html {
  if (typeof value !== 'string') throw new TypeError('Expected text string');
  return node({ kind: 'text', value });
}
export function fragment(value: Children): Html {
  return node({ kind: 'fragment', children: children(value) });
}
export function element(tag: string, attrs: Attributes = {}, content: Children = []): Html {
  return node({
    kind: 'element',
    props: props({ tag, attrs }, { tag: 'string', attrs: 'attrs' }),
    children: children(content),
  });
}
export function button(content: Children, options: ButtonProps = {}): Html {
  return node({
    kind: 'button',
    children: children(content),
    props: props(options, {
      ...common,
      variant: ['primary', 'secondary', 'ghost', 'destructive', 'secondary-destructive', 'outline'],
      size: sizes,
      disabled: 'boolean',
      type: ['button', 'submit', 'reset'],
    }),
  });
}
export function input(options: InputProps): Html {
  const value = props(options, {
    ...common,
    id: 'string',
    size: sizes,
    variant: ['default', 'error'],
    label: 'child',
    description: 'child',
    error: 'child',
    placeholder: 'string',
    disabled: 'boolean',
    required: 'boolean',
  });
  if (typeof value.id !== 'string' || !value.id.trim() || /\s/.test(value.id))
    throw new TypeError('Input requires a nonempty caller-provided id without whitespace');
  return node({ kind: 'input', props: value });
}
export function textComponent(content: Children, options: TextProps = {}): Html {
  return node({
    kind: 'textComponent',
    children: children(content),
    props: props(options, {
      ...common,
      variant: ['heading', 'body', 'secondary', 'success', 'error', 'mono', 'mono-secondary'],
      size: sizes,
      as: 'string',
      bold: 'boolean',
      truncate: 'boolean',
    }),
  });
}
export function layerCard(content: Children, options: LayerCardProps = {}): Html {
  return node({
    kind: 'layerCard',
    children: children(content),
    props: props(options, { ...common, layered: 'boolean' }),
  });
}
export function layerCardPrimary(content: Children): Html {
  return node({ kind: 'layerCardPrimary', children: children(content) });
}
export function layerCardSecondary(content: Children): Html {
  return node({ kind: 'layerCardSecondary', children: children(content) });
}
export function appShell(options: AppShellProps): Html {
  const { children: content, ...rest } = options;
  const value = props(rest, {
    brand: 'child',
    navigationTrigger: 'child',
    globalSearch: 'child',
    headerActions: 'child',
    accountMenu: 'child',
    rail: 'child',
    sidebar: 'child',
    tabs: 'child',
    contextPanel: 'child',
    bottomBar: 'child',
    contextPanelLabel: 'string',
    closeContextPanelLabel: 'string',
    primaryNavigationLabel: 'string',
    workspaceNavigationLabel: 'string',
    closeWorkspaceNavigationLabel: 'string',
    sidebarCollapsed: 'boolean',
    mobileSidebarOpen: 'boolean',
    contextPanelOpen: 'boolean',
  });
  if (!Object.hasOwn(value, 'brand')) throw new TypeError('AppShell requires brand');
  return node({ kind: 'appShell', props: value, children: children(content) });
}
export function renderHtml(value: Html): string {
  if (!value || typeof value !== 'object' || !nodes.has(value))
    throw new TypeError('Expected a Yami-kumo Html node');
  return render(JSON.stringify(nodes.get(value)));
}
