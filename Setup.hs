{-# OPTIONS_GHC -Wall #-}
import System.FilePath ( (</>), (<.>) )

import Distribution.PackageDescription
import Distribution.Simple
import Distribution.Simple.BuildPaths ( autogenPackageModulesDir )
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.Setup as S
import Distribution.Simple.Utils
import Distribution.Text ( display )

import Distribution.ModuleName (ModuleName)
import qualified Distribution.ModuleName as ModuleName

import qualified GetText as GetText

main :: IO ()
main = defaultMainWithHooks $ installBustleHooks simpleUserHooks

-- Okay, so we want to use hgettext's install hook, but not the hook that
-- miraculously runs all our code through CPP just to add a couple of
-- constants. (cpp doesn't like multi-line Haskell strings, so this is not
-- purely an academic preference.)
--
-- Instead, we generate GetText_bustle.hs which contains the constants, in the
-- same way as Paths_bustle.hs gets generated by Cabal. Much neater.
--
-- TODO: upstream this to hgettext
installBustleHooks :: UserHooks
                   -> UserHooks
installBustleHooks uh = uh
  { postInst = \a b c d -> do
        postInst uh a b c d
        GetText.installPOFiles a b c d
  , buildHook = \pkg lbi hooks flags -> do
        writeGetTextConstantsFile pkg lbi flags
        buildHook uh pkg lbi hooks flags
  }


writeGetTextConstantsFile :: PackageDescription -> LocalBuildInfo -> BuildFlags -> IO ()
writeGetTextConstantsFile pkg lbi flags = do
    let verbosity = fromFlag (buildVerbosity flags)

    createDirectoryIfMissingVerbose verbosity True (autogenPackageModulesDir lbi)

    let pathsModulePath = autogenPackageModulesDir lbi
                      </> ModuleName.toFilePath (getTextConstantsModuleName pkg) <.> "hs"
    rewriteFile pathsModulePath (generateModule pkg lbi)

getTextConstantsModuleName :: PackageDescription -> ModuleName
getTextConstantsModuleName pkg_descr =
  ModuleName.fromString $
    "GetText_" ++ fixedPackageName pkg_descr

-- Cargo-culted from two separate places in Cabal!
fixedPackageName :: PackageDescription -> String
fixedPackageName = map fixchar . display . packageName
  where fixchar '-' = '_'
        fixchar c   = c

generateModule :: PackageDescription -> LocalBuildInfo -> String
generateModule pkg lbi =
    header ++ body
  where
    moduleName = getTextConstantsModuleName pkg

    header =
        "module " ++ display moduleName ++ " (\n"++
        "    getMessageCatalogDomain,\n" ++
        "    getMessageCatalogDir\n" ++
        ") where\n"++
        "\n" ++
        "import qualified Control.Exception as Exception\n" ++
        "import System.Environment (getEnv)\n"

    body =
        "catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a\n" ++
        "catchIO = Exception.catch\n" ++
        "\n" ++
        "getMessageCatalogDomain :: IO String\n" ++
        "getMessageCatalogDomain = return " ++ show dom ++ "\n" ++
        "\n" ++
        "messageCatalogDir :: String\n" ++
        "messageCatalogDir = " ++ show tar ++ "\n" ++
        "\n" ++
        "getMessageCatalogDir :: IO FilePath\n" ++
        "getMessageCatalogDir = catchIO (getEnv \"" ++ fixedPackageName pkg ++ "_localedir\") (\\_ -> return messageCatalogDir)\n"

    sMap = customFieldsPD (localPkgDescr lbi)
    dom = GetText.getDomainNameDefault sMap (GetText.getPackageName lbi)
    tar = GetText.targetDataDir lbi

-- Cargo-culted from hgettext
