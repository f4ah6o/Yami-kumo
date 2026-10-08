import { Button, Input, LayerCard, Text } from '@cloudflare/kumo';
import { flushSync } from 'react-dom';
import { createRoot, type Root } from 'react-dom/client';
import { useState } from 'react';
import caseManifest from '../fixtures/kumo-cases.json';
import { enhanceYamiKumo, renderParityCase } from '../_build/js/release/build/browser/browser.js';
import { AppShell } from './shell/AppShell';
import './parity.css';

type Source = 'react' | 'moonbit';

interface Interaction {
  type: string;
  target: string;
  value?: string;
  viewports?: string[];
  expectText?: string;
  expect?: { attribute?: string; value?: string; text?: string };
}

interface ParityCase {
  id: string;
  component: 'button' | 'input' | 'text' | 'layerCard' | 'appShell';
  content?: string;
  props: Record<string, unknown>;
  interactions: Interaction[];
}

const cases = caseManifest.cases as ParityCase[];
let activeReactRoot: Root | null = null;
let selectedCase = cases[0]?.id ?? '';
let selectedSource: Source = 'react';

declare global {
  interface Window {
    parityKumoVersion: string;
    mountParity(options: { caseId: string; source: Source }): void;
    unmountParity(): void;
  }
}

window.parityKumoVersion = __KUMO_VERSION__;

function mountParity({ caseId, source }: { caseId: string; source: Source }) {
  const testCase = cases.find((candidate) => candidate.id === caseId);
  const host = document.getElementById('parity-mount-slot');
  if (!testCase || !host) throw new Error(`Unknown parity case or missing mount: ${caseId}`);

  window.unmountParity();
  selectedCase = caseId;
  selectedSource = source;
  host.replaceChildren();

  if (source === 'moonbit') {
    const candidateRoot = document.createElement('div');
    candidateRoot.className = 'parity-mounted-root';
    candidateRoot.dataset.parityRoot = '';
    candidateRoot.dataset.caseId = caseId;
    candidateRoot.dataset.source = source;
    candidateRoot.innerHTML = renderParityCase(JSON.stringify(testCase));
    host.append(candidateRoot);
    enhanceYamiKumo();
    installMoonBitInteractions(candidateRoot);
  } else {
    activeReactRoot = createRoot(host);
    flushSync(() => {
      activeReactRoot?.render(
        <div
          className="parity-mounted-root"
          data-parity-root
          data-case-id={caseId}
          data-source={source}
        >
          <ReactKumoCase key={`${caseId}:${source}`} testCase={testCase} />
        </div>,
      );
    });
  }

  updateControls();
}

function unmountParity() {
  activeReactRoot?.unmount();
  activeReactRoot = null;
  document.getElementById('parity-mount-slot')?.replaceChildren();
}

window.mountParity = mountParity;
window.unmountParity = unmountParity;

function ReactKumoCase({ testCase }: { testCase: ParityCase }) {
  const [saved, setSaved] = useState(false);
  const props = testCase.props as Record<string, any>;
  const target = props.target as string | undefined;

  switch (testCase.component) {
    case 'button':
      return (
        <Button
          variant={props.variant}
          size={props.size}
          disabled={props.disabled}
          type={props.type ?? 'button'}
          data-parity-target={target}
          onClick={() => setSaved(true)}
        >
          {saved ? 'Saved' : testCase.content}
        </Button>
      );
    case 'input':
      if (props.grouped) {
        return (
          <>
            <Input
              id={props.firstId}
              label={props.firstLabel}
              description={props.firstDescription}
              data-parity-target={props.firstTarget}
            />
            <Input
              id={props.secondId}
              label={props.secondLabel}
              description={props.secondDescription}
              error={props.secondError}
              data-parity-target={props.secondTarget}
            />
          </>
        );
      }
      return (
        <Input
          id={props.id}
          size={props.size}
          variant={props.variant}
          label={props.label}
          description={props.description}
          error={props.error || undefined}
          placeholder={props.placeholder}
          aria-label={props.ariaLabel}
          disabled={props.disabled}
          required={props.required}
          defaultValue={props.value}
          data-parity-target={target}
        />
      );
    case 'text':
      return (
        <Text
          variant={props.variant}
          size={props.size}
          as={props.as}
          bold={props.bold}
          truncate={props.truncate}
        >
          {testCase.content}
        </Text>
      );
    case 'layerCard':
      return (
        <LayerCard>
          {props.layered ? (
            <>
              <LayerCard.Secondary>{props.secondary}</LayerCard.Secondary>
              <LayerCard.Primary>{testCase.content}</LayerCard.Primary>
            </>
          ) : (
            testCase.content
          )}
        </LayerCard>
      );
    case 'appShell':
      return <ReactAppShell testCase={testCase} />;
  }
}

function ReactAppShell({ testCase }: { testCase: ParityCase }) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const props = testCase.props as Record<string, any>;
  const trigger = props.full ? (
    <button
      type="button"
      aria-controls="yk-mobile-navigation"
      aria-expanded={sidebarOpen}
      data-parity-target="nav-trigger"
      onClick={() => setSidebarOpen((open) => !open)}
      onKeyDown={(event) => {
        if (event.key === 'Escape') setSidebarOpen(false);
      }}
    >
      {props.triggerLabel}
    </button>
  ) : undefined;

  return (
    <AppShell
      brand={props.brand}
      navigationTrigger={trigger}
      globalSearch={props.full ? props.search : undefined}
      headerActions={props.full ? props.headerActions : undefined}
      accountMenu={props.full ? props.accountMenu : undefined}
      rail={props.full ? props.rail : undefined}
      sidebar={props.full ? props.sidebar : undefined}
      tabs={props.full ? props.tabs : undefined}
      contextPanel={props.full ? props.contextPanel : undefined}
      contextPanelLabel={props.contextPanelLabel}
      closeContextPanelLabel={props.closeContextPanelLabel}
      primaryNavigationLabel={props.primaryNavigationLabel}
      workspaceNavigationLabel={props.workspaceNavigationLabel}
      closeWorkspaceNavigationLabel={props.closeWorkspaceNavigationLabel}
      bottomBar={props.full ? props.bottomBar : undefined}
      sidebarCollapsed={props.sidebarCollapsed}
      mobileSidebarOpen={sidebarOpen}
      onMobileSidebarDismiss={() => setSidebarOpen(false)}
    >
      {testCase.content}
    </AppShell>
  );
}

function installMoonBitInteractions(root: HTMLElement) {
  root.addEventListener('click', (event) => {
    const source = event.target;
    if (!(source instanceof Element)) return;
    const target = source.closest<HTMLElement>('[data-parity-target]');
    if (!target) return;

    if (target.dataset.parityTarget === 'nav-trigger') {
      const shell = root.querySelector<HTMLElement>('.yk-shell');
      if (!shell) return;
      const isOpen = shell.dataset.mobileSidebarOpen === 'true';
      shell.dataset.mobileSidebarOpen = String(!isOpen);
      target.setAttribute('aria-expanded', String(!isOpen));
      return;
    }

    const contents = target.querySelector<HTMLElement>('.contents');
    if (contents) contents.textContent = 'Saved';
    else target.textContent = 'Saved';
  });

  root.addEventListener('keydown', (event) => {
    if (!(event instanceof KeyboardEvent) || event.key !== 'Escape') return;
    const shell = root.querySelector<HTMLElement>('.yk-shell');
    const trigger = root.querySelector<HTMLElement>('[data-parity-target="nav-trigger"]');
    if (shell && trigger) {
      shell.dataset.mobileSidebarOpen = 'false';
      trigger.setAttribute('aria-expanded', 'false');
    }
  });
}

function updateControls() {
  const caseSelect = document.getElementById('parity-case-select') as HTMLSelectElement | null;
  const sourceSelect = document.getElementById('parity-source-select') as HTMLSelectElement | null;
  if (caseSelect) caseSelect.value = selectedCase;
  if (sourceSelect) sourceSelect.value = selectedSource;
}

function ParityGallery() {
  const [caseId, setCaseId] = useState(selectedCase);
  const [source, setSource] = useState<Source>(selectedSource);

  const mount = (nextCase = caseId, nextSource = source) => {
    setCaseId(nextCase);
    setSource(nextSource);
    mountParity({ caseId: nextCase, source: nextSource });
  };

  return (
    <main className="parity-page" data-kumo-version={__KUMO_VERSION__}>
      <header className="parity-toolbar">
        <div>
          <h1>Yami-kumo parity gallery</h1>
          <p>Real React Kumo and the compiled MoonBit renderer, mounted independently.</p>
        </div>
        <label>
          Case
          <select
            id="parity-case-select"
            value={caseId}
            onChange={(event) => mount(event.currentTarget.value, source)}
          >
            {cases.map((candidate) => (
              <option key={candidate.id} value={candidate.id}>
                {candidate.id}
              </option>
            ))}
          </select>
        </label>
        <label>
          Source
          <select
            id="parity-source-select"
            value={source}
            onChange={(event) => mount(caseId, event.currentTarget.value as Source)}
          >
            <option value="react">React Kumo</option>
            <option value="moonbit">Compiled MoonBit</option>
          </select>
        </label>
      </header>
      <section className="parity-testbed" aria-label="Parity testbed">
        <div id="parity-mount-slot" />
      </section>
      <footer className="parity-footer">
        <span>Installed Kumo: {__KUMO_VERSION__}</span>
        <span>{cases.length} canonical cases · independent source mounts</span>
      </footer>
    </main>
  );
}

export function mountParityGallery(root: HTMLElement) {
  const galleryRoot = createRoot(root);
  flushSync(() => galleryRoot.render(<ParityGallery />));
  mountParity({ caseId: cases[0].id, source: 'react' });
  return () => {
    window.unmountParity();
    galleryRoot.unmount();
  };
}
