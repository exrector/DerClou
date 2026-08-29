#if UNITY_EDITOR
namespace DerClou.Editor
{
    using UnityEditor;
    using UnityEditor.TestTools.TestRunner.Api;
    using UnityEngine;

    public static class DerClouTestRunner
    {
        private static TestRunnerApi runner;
        private static ResultLogger logger;

        [MenuItem("Tools/DerClou/Run EditMode Tests")]
        public static void RunEditModeTests()
        {
            runner = ScriptableObject.CreateInstance<TestRunnerApi>();
            logger = new ResultLogger();
            runner.RegisterCallbacks(logger);
            runner.Execute(new ExecutionSettings(
                new Filter { testMode = TestMode.EditMode }));
        }

        private sealed class ResultLogger : ICallbacks
        {
            private int passed;
            private int failed;
            private int skipped;

            public void RunStarted(ITestAdaptor testsToRun) { }

            public void RunFinished(ITestResultAdaptor result)
            {
                Debug.Log($"[DerClou Tests] passed={passed} failed={failed} skipped={skipped}");
                if (runner != null && logger != null) runner.UnregisterCallbacks(logger);
                runner = null;
                logger = null;
            }

            public void TestStarted(ITestAdaptor test) { }

            public void TestFinished(ITestResultAdaptor result)
            {
                if (result.HasChildren) return;
                switch (result.TestStatus)
                {
                    case TestStatus.Passed: passed++; break;
                    case TestStatus.Failed:
                        failed++;
                        Debug.LogError($"[DerClou Test Failed] {result.FullName}: {result.Message}\n{result.StackTrace}");
                        break;
                    default: skipped++; break;
                }
            }
        }
    }
}
#endif
