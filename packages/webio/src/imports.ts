import SystemJS, {Config as SystemJSConfig} from "systemjs";
import createLogger from "debug";
const debug = createLogger("WebIO:imports");

/**
 * Possible types of import specifiers.
 *
 * See {@link BlockImport} and {@link ConcreteImport} and their child
 * interfaces for more information.
 */
export const enum ImportType {
  SYNC_BLOCK = "sync_block",
  ASYNC_BLOCK = "async_block",
  JS = "js",
  CSS = "css",
  HTML = "html",
}

/**
 * All possible block imports.
 *
 * See {@link BlockImportBase}.
 */
export type BlockImport = SyncBlockImport | AsyncBlockImport;

/**
 * The value obtained from importing a block.
 */
export type BlockImportResult = ConcreteImportResult[];

/**
 * All possible concrete imports.
 *
 * See {@link ConcreteImport}.
 */
export type ConcreteImport = JSImport | CSSImport | HTMLImport;

/**
 * Possible types for a concrete import.
 *
 * Currently, we can't be any more specific than "any". `null` is returned for
 * non-JS-module imports.
 */
export type ConcreteImportResult = any | null;

/**
 * Abstract base interface for all imports.
 *
 * See {@link BlockImport} and {@link ConcreteImport} and their child
 * interfaces for more information.
 */
export interface ImportBase {
  type: ImportType;
}

/**
 * Abstract base interface for block imports.
 *
 * A block import is better though of as a block _of_ imports. All the things
 * specified by the block import need to be individually imported.
 */
export interface BlockImportBase extends ImportBase {
  data: ConcreteImport[];
}

/**
 * Abstract base interface for concrete imports.
 *
 * A concrete import is some logical single resource/entity (e.g. a stylesheet
 * or a JavaScript file).
 */
export interface ConcreteImportBase extends ImportBase {
  name: string | null;
  url?: string;
  blob?: string;
}

/**
 * A block import that loads its sub-imports sequentially.
 *
 * E.g. if data is `[A, B]`, then `A` completes loading before `B` begins to
 * load.
 */
export interface SyncBlockImport extends BlockImportBase {
  type: ImportType.SYNC_BLOCK;
}

/**
 * A block import that loads it sub-imports asynchronously and concurrently.
 *
 * E.g. if data is `[A, B]`, then `A` and `B` are loaded in no particular order
 * and no guarantees are made as to which will finish first or if one will be
 * loaded before the other.
 */
export interface AsyncBlockImport extends BlockImportBase {
  type: ImportType.ASYNC_BLOCK;
}

/**
 * A concrete import for a JavaScript file/script/library.
 */
export interface JSImport extends ConcreteImportBase {
  type: ImportType.JS;
}

/**
 * A concrete import for a CSS stylesheet/snippet.
 */
export interface CSSImport extends ConcreteImportBase {
  type: ImportType.CSS;
}

/**
 * A concrete import for an HTML file/snippet.
 */
export interface HTMLImport extends ConcreteImportBase {
  type: ImportType.HTML;
}

const URL_PROTOCOL_REGEX = /[A-Za-z]+:\/\//;

const isRelativeUrl = (url: string) => {
  return !(URL_PROTOCOL_REGEX.test(url) || url.startsWith("//"));
};

let _lastImportNumber = 0;
const uniqueImportName = () => `import_${_lastImportNumber += 1}`;

export const importJSUrl = (name: string, url: string) => {
  debug(`Importing JavaScript resource (${name}) from url (${url}).`);
  SystemJS.config({
    paths: {
      [name]: url,
    },
    meta: {
      [name]: {
        authorization: isRelativeUrl(url),
      }
    }
  });
  return SystemJS.import(url);
};

export const importJS = (importData: JSImport): any => {
  debug("Importing JavaScript resource.", importData);
  const {url, blob} = importData;
  const name = importData.name || uniqueImportName();

  if (blob) {
    throw new Error(`Importing JS blob is not yet implemented.`);
  } else if (url) {
    return importJSUrl(name, url);
  } else {
    throw new Error(`One of blob or url must be specified in call to importJS.`);
  }
};

/**
 * Import some href/url in a `<link />` tag.
 * @param url
 */
export const importLink = (url: string, options: {rel?: string, type?: string, media?: string}) => {
  if (document.querySelector(`link[data-webio-import="${url}"]`)) {
    debug("CSS resource (${url}) is already imported.");
    // This actually has a slight race condition where if the import actually
    // is still loading, we'll resolve immediately. Probably(?) not a big deal.
    return Promise.resolve();
  }

  return new Promise<void>((resolve, reject) => {
    const link = document.createElement("link");

    // Apply options
    const {rel, type, media} = options;
    rel && (link.rel = rel);
    type && (link.type = type);
    media && (link.media = media);

    link.href = url;
    link.setAttribute("async", "");
    link.onload = () => resolve();
    link.onerror = () => {
      link.remove();
      reject();
    };
    document.head!.appendChild(link);
  });
};

export const importCSS = (importData: CSSImport) => {
  debug("Importing CSS resource.", importData);
  const {url, blob} = importData;
  if (url) {
    return importLink(url, {
      rel: "stylesheet",
      type: "text/css",
      media: "all"
    });
  } else if (blob) {
    throw new Error(`Imports CSS blob is not yet implemented.`);
  } else {
    throw new Error(`One of blob or url must be specified in call to importCSS.`);
  }
};

export const importSyncBlock = async (importData: SyncBlockImport): Promise<BlockImportResult> => {
  debug("Importing synchronous block.", importData);
  const results = [];
  for (const importItem of importData.data) {
    results.push(await importResource(importItem));
  }
  return results;
};

export const importAsyncBlock = async (importData: AsyncBlockImport): Promise<BlockImportResult> => {
  debug("Importing asynchronous block.", importData);
  return Promise.all(importData.data.map(importResource));
};

/**
 * Import a _thing_.
 * @param importData
 */
export const importResource = (importData: ConcreteImport): any | null => {
  switch (importData.type) {
    case ImportType.JS:
      return importJS(importData);

    case ImportType.CSS:
      return importCSS(importData);

    default:
      throw new Error(`Importing resource of type "${importData.type}" not supported.`);
  }
};

export const importBlock = (importData: BlockImport, config?: SystemJSConfig) => {
  if (config) {
    SystemJS.config(config);
  }
  switch (importData.type) {
    case ImportType.SYNC_BLOCK:
      return importSyncBlock(importData);
    case ImportType.ASYNC_BLOCK:
      return importAsyncBlock(importData);
    default:
      throw new Error(`Cannot import unknown block type: ${(importData as any).type}.`);
  }
};

console.warn("WebIO is registering SystemJS window global.");
(window as any).SystemJS = SystemJS;
if (!!SystemJS._nodeRequire) {
  // Fixes https://github.com/systemjs/systemjs/issues/1817
  // SystemJS basically will try to detect if it should use NodeJS's built-in
  // require to load things if it can, but because Webpack (sometimes, depending
  // on the settings/target I think?) defines `require`, SystemJS can get
  // confused. When it gets confused, it tries to use Webpack's require (which
  // then complains since the things we're trying to load dynamically weren't
  // loaded by Webpack). This is our hack to un-confuse SystemJS.
  console.warn("Monkey-patchings SystemJS._nodeRequire to undefined.");
  (SystemJS as any)._nodeRequire = undefined;
}
