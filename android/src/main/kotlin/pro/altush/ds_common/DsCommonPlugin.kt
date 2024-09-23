package pro.altush.ds_common

import android.content.Context

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener

/** DsCommonPlugin */
class DsCommonPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ds_common")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "fetchInstallReferrer") {
            fetchInstallReferrer(result)
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun fetchInstallReferrer(result: Result) {
        val installReferrerClient: InstallReferrerClient =
            InstallReferrerClient.newBuilder(context.applicationContext)
                .build()
        installReferrerClient.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                when (responseCode) {
                    InstallReferrerClient.InstallReferrerResponse.OK -> {
                        try {
                            val mAppReferrerLink = installReferrerClient.installReferrer.installReferrer
                            if (mAppReferrerLink == null) {
                                result.success("null")
                            } else {
                                result.success(mAppReferrerLink)
                            }
                        } catch (e: Throwable) {
                            result.error("installReferrer native error: ${e.message}", null, null)
                        }
                    }
                    InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> {
                        result.error("installReferrer: feature not supported", null, null)
                    }
                    InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE -> {
                        result.error("installReferrer: service unavailable", null, null)
                    }
                    InstallReferrerClient.InstallReferrerResponse.SERVICE_DISCONNECTED -> {
                        result.error("installReferrer: service disconnected", null, null)
                    }
                    InstallReferrerClient.InstallReferrerResponse.DEVELOPER_ERROR -> {
                        result.error("installReferrer: developer error", null, null)
                    }
                }
                installReferrerClient.endConnection()
            }

            override fun onInstallReferrerServiceDisconnected() {
                result.success("null")
            }
        })
    }

}
