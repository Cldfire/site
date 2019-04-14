+++
title = "Writing an OpenCL Filter for FFmpeg"
# TODO: Date
date = 2019-04-14
draft = true
+++

April has arrived. Spring is in the air, the sun is beginning to shine, temperatures are starting to rise, and Google Summer of Code 2019's student application period has just passed. This is the first year that I'm eligible to apply (the freshly-minted eighteen-year-old that I am), and the project that caught my eye involved porting FFmpeg's CPU video filters to the GPU via OpenCL. As an amateur video editor / videographer and a programmer fascinated by the GPU, its an exciting project that's relevant to my interests, and since that's one of the ideals of GSoC, I figured, why not give it a shot? I also decided it would be the perfect time to start a blog with my shiny new `.dev` domain in order to document my journey completing the qualification task and writing a simple OpenCL filter for FFmpeg.

I aim to make this post useful for anyone looking to get started writing such filters for FFmpeg (perhaps for this same GSoC project in future years?).

Let's begin.

## Building FFmpeg

First things first: you're going to need to have a few libraries installed on your system in order to build FFmpeg with OpenCL features. The following only applies to Arch Linux and an NVIDIA GPU, so if you're using a different distro and/or hardware, you'll need to research the appropriate packages yourself for this step (take a read through [FFmpeg's compilation guides](https://trac.ffmpeg.org/wiki/CompilationGuide) and possibly [the Arch wiki's GPGPU page](https://wiki.archlinux.org/index.php/GPGPU)). 

If you're using Windows, [good](https://trac.ffmpeg.org/wiki/CompilationGuide/MinGW) [luck](https://trac.ffmpeg.org/wiki/CompilationGuide/MSVC) [friend](https://trac.ffmpeg.org/wiki/CompilationGuide/CrossCompilingForWindows).

Since I'm going to be on Arch for the duration of this blog post, however, I can easily grab the necessary packages via `pacman` (note that it is assumed that standard development packages such as a C compiler, make, etc., are already installed):

```
sudo pacman -S x264 opencl-headers yasm opencl-nvidia ocl-icd
```

`x264` provides support for encoding h.264. The `opencl-headers` provide the header files that the FFmpeg source references. `yasm` is an assembler that is used to compile various assembly components in FFmpeg for improved performance. The `opencl-nvidia` package is NVIDIA's official OpenCL runtime (the piece that actually executes the OpenCL code that I'll be writing), and `ocl-icd` is an Arch-maintained package that provides an implementation of an Installable Client Driver (ICD) loader for OpenCL (a tool that takes care of loading the different vendors' OpenCL runtimes across all platforms).

Next, you need to clone the FFmpeg source (replace `some/path` with something that works well for you):

```
git clone git://source.ffmpeg.org/ffmpeg some/path
```

Now that you have the necessary packages installed and FFmpeg cloned, you're ready to configure the build (run from the root of your FFmpeg clone):

```
./configure --enable-nonfree --enable-gpl --enable-libx264 --enable-opencl
```

And finally, build FFmpeg (set the number of build jobs to a number that makes sense for your hardware):

```
make -j 8
```

After some minutes pass, you should see the various FFmpeg binaries appear in the root of your FFmpeg clone; if not, troubleshooting build failures is outside the scope of this post. Come back when your build is finished successfully!

## Testing an Existing Filter

The first thing we'll do is try out one of the existing OpenCL filters, both to make sure that they are functioning properly (meaning our OpenCL install is in good order) and to make sure that we know how to use them (since we'll be needing to run them quite a bit when we begin writing our own). We are, of course, going to need some kind of input to process. This being my blog, I'm obligated to direct you to download my own content ;) (install `youtube-dl` with `pacman` if you don't have it already and put the video file wherever you'd like):

```
youtube-dl https://www.youtube.com/watch?v=qdMR2jTTh_w
```

*Disclaimer: use of my video is not required for those who dislike Rocket League*

Let's do a quick trim to fifteen seconds long with our freshly-built FFmpeg binary, transcoding to h264 in the `.mp4` container while we're at it:

```
./ffmpeg -i ../path_to_video.webm -ss 00:00:30 -to 00:00:45 ../trimmed_video.mp4
```

This command takes the downloaded video as input, seeks to the thirty second mark, and then re-encodes the video in the h264 codec, cutting the video off at forty-five seconds. You can test viewing the file with your browser (in my case, `firefox ../trimmed_video.mp4`).

Next, we'll try a run of the `avgblur` filter with a radius of ten on the CPU:

```
time ./ffmpeg -i ../trimmed_video.mp4 -vf "avgblur=10" ../trimmed_video_blurred_cpu.mp4
```

Our naive measurement of how long the process took, using the `time` command, gives the following:

```
real    0m37.814s
user    4m30.294s
sys     0m1.332s
```

Comparing that to the `avgblur_opencl` filter:

```
time ./ffmpeg -init_hw_device opencl=gpu -filter_hw_device gpu -i ../trimmed_video.mp4 -vf "hwupload, avgblur_opencl=10, hwdownload" ../trimmed_video_blurred_opencl.mp4
```

There's more going on in this invocation of `ffmpeg`, so I'm going to break it down a bit. We're initializing a hardware device for OpenCL and naming it 'gpu' via the `-init-hw-device` flag. We're then setting the hardware device for hardware-accelerated filters to that device using the `-filter_hw_device` flag. Finally, we're changing the filter string to upload our video frames to the GPU before running the `avgblur_opencl` filter and download them from it afterwards through the addition of `hwupload` and `hwdownload` in the appropriate positions.

The times for this invocation:

```
real    0m29.406s
user    3m26.989s
sys     0m2.855s
```

So, although our measurements are certainly not very scientific, we can at least conclude that despite now having to upload and download the video frames to and from the GPU, using OpenCL filters has actually cut the overall execution time by over twenty percent and also reduced the amount of CPU time used.

Additionally, if we take a look at the output of `nvidia-smi` while performing the above operation with the OpenCL filter:

```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 418.56       Driver Version: 418.56       CUDA Version: 10.1     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  GeForce GTX 980 Ti  Off  | 00000000:01:00.0  On |                  N/A |
| 30%   60C    P2    95W / 275W |    911MiB /  6080MiB |     12%      Default |
+-------------------------------+----------------------+----------------------+
                                                                               
+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID   Type   Process name                             Usage      |
|=============================================================================|
|    0       715      G   /usr/lib/Xorg                                481MiB |
|    0       736      G   compton                                        3MiB |
|    0      3925      C   ./ffmpeg                                     116MiB |
+-----------------------------------------------------------------------------+
```

We notice that there's a moderate amount of GPU usage showing up in concert with our FFmpeg binary being listed as a compute process. Nice!

On to writing a filter of our own.

## Finding a Filter to Port

According to the wiki entry for the GSoC project, the new filter that I was supposed to implement could either be a copy of an existing filter or an entirely new one, and it didn't have to "be efficient or do anything complex." That's good! There was a lot to learn (both about the FFmpeg codebase and the email-oriented development workflow); keeping the filter simple made it a lot easier to become acquainted with those things.

After scrolling through the list of existing CPU filters for a while, I eventually stumbled upon one titled `colorkey` that was short and structured in a way that I figured would make it reasonably straightforward to port to OpenCL. Specifically, I immediately noticed that the filter:

* Was already designed in a multi-threaded manner (and I know that we're essentially going to be writing a version that runs on a drastically increased number of "threads").
* Already had the exact code that would need to be run via OpenCL factored out into a single function (`do_colorkey_pixel`).

Now it's time to familiarize ourselves with the code.

## Overview of the `colorkey` CPU Filter

Here is a version of the `vf_colorkey.c` file that we're going to be discussing with almost everything but the declarations cut out:

```c
typedef struct ColorkeyContext {
    // ...
} ColorkeyContext;

static uint8_t do_colorkey_pixel(ColorkeyContext *ctx, uint8_t r, uint8_t g, uint8_t b)
{
    // ...
}

static int do_colorkey_slice(AVFilterContext *avctx, void *arg, int jobnr, int nb_jobs)
{
    // ...
}

static int filter_frame(AVFilterLink *link, AVFrame *frame)
{
    // ...
}

static av_cold int config_output(AVFilterLink *outlink)
{
    // ...
}

static av_cold int query_formats(AVFilterContext *avctx)
{
    // ...
}

static const AVFilterPad colorkey_inputs[] = {
    // ...
};

static const AVFilterPad colorkey_outputs[] = {
    // ...
};

static const AVOption colorkey_options[] = {
    // ...
};

AVFILTER_DEFINE_CLASS(colorkey);

AVFilter ff_vf_colorkey = {
    // ...
};
```

The `ColorkeyContext` struct at the top is the state of the filter: it contains any data that is needed throughout an instances' execution lifetime, such as values that were passed to the filter as arguments and a pointer to a class that contains information about the filter itself.

Next I'm actually going to go all the way to the bottom and talk about the boilerplate that is found there. As you'll see very shortly when we start the OpenCL port, the `AVFilter` variable named `ff_vf_colorkey` is the high-level structure that contains all of the information about the filter (its name, inputs, outputs, the callback to negotiate formats, the size of its context structure, and more). One of its fields is set to the class that the macro `AVFILTER_DEFINE_CLASS` defines immediately above it; other things that go inside it are `colorkey_outputs` (each array element is an output pad that the filter supports along with its associated data; the `config_output` function is passed as a callback here), `colorkey_inputs` (previous but for inputs), and `query_formats` (a function passed as a callback to negotiate what formats the filter accepts as input).

Finally, it's time to look at the functions where the actual filter work happens.

```c
static int filter_frame(AVFilterLink *link, AVFrame *frame)
{
    // ...
}
```

The `filter_frame` function is passed as a callback to the single element of the `colorkey_inputs` array. It is the function that gets called to process every frame of input that gets passed for that particular input pad. We're provided with an `AVFrame` that contains said frame input as well as a pointer to an `AVFilterLink` that represents a link between our filter and the one before it that is providing us with input (from which we can gain access to all kinds of contextual stuff that's needed to write the body of the function).

```c
static int do_colorkey_slice(AVFilterContext *avctx, void *arg, int jobnr, int nb_jobs)
{
    // ...
}
```

This `do_colorkey_slice` function is irrelevant to us since it's used to implement the CPU multi-threading that we're about to be replacing, so I won't discuss it further.

```c
static uint8_t do_colorkey_pixel(ColorkeyContext *ctx, uint8_t r, uint8_t g, uint8_t b)
{
    // ...
}
```

Here is the aforementioned `do_colorkey_pixel` function that was the reason this filter caught my eye in the first place. This function contains the code that runs the formulaic portion of the filter that we'll be needing to translate into an OpenCL kernel.

That pretty much does it for the CPU version of the filter. It's time to heat up our GPU!

## Writing the `colorkey_opencl` Filter

*Note: feel free to look everything up in the FFmpeg source if you would like to see the full code at any point*

Before we can get to the actually exciting part we unfortunately have some boilerplate to get out of the way. Let's put it in a new file (`libavfilter/vf_colorkey_opencl.c`) that contains a copy-pasted header and list of includes from one of the other OpenCL filters. We'll start off by defining the context:

```c
typedef struct ColorkeyOpenCLContext {
    OpenCLFilterContext ocf;
    // Whether or not the above `OpenCLFilterContext` has
    // been initialized
    int initialized;

    cl_command_queue command_queue;
    cl_kernel kernel_colorkey;

    uint8_t colorkey_rgba[4];
    // Stored as a normalized float for passing to the OpenCL kernel
    cl_float4 colorkey_rgba_float;
    float similarity;
    float blend;
} ColorkeyOpenCLContext;
```

Much of this is copied from the CPU filter. Since we're now writing an OpenCL filter, however, we're also adding an `OpenCLFilterContext` that contains additional stuff relevant for OpenCL filters, a variable to track whether or not that context has been initialized, a `cl_command_queue` that we'll use to submit work for OpenCL to do, a `cl_kernel` field that will store the actual code that OpenCL will be executing, and a `cl_float4` that will hold the RGBA color we are supposed to be matching against as a normalized float for use in the OpenCL kernel.

Now for all of the "bottom-of-the-file" things:

```c
#define OFFSET(x) offsetof(ColorkeyOpenCLContext, x)
#define FLAGS AV_OPT_FLAG_FILTERING_PARAM|AV_OPT_FLAG_VIDEO_PARAM

static const AVOption colorkey_opencl_options[] = {
    { "color", "set the colorkey key color", OFFSET(colorkey_rgba), AV_OPT_TYPE_COLOR, { .str = "black" }, CHAR_MIN, CHAR_MAX, FLAGS },
    { "similarity", "set the colorkey similarity value", OFFSET(similarity), AV_OPT_TYPE_FLOAT, { .dbl = 0.01 }, 0.01, 1.0, FLAGS },
    { "blend", "set the colorkey key blend value", OFFSET(blend), AV_OPT_TYPE_FLOAT, { .dbl = 0.0 }, 0.0, 1.0, FLAGS },
    { NULL }
};

AVFILTER_DEFINE_CLASS(colorkey_opencl);

AVFilter ff_vf_colorkey_opencl = {
    .name           = "colorkey_opencl",
    .description    = NULL_IF_CONFIG_SMALL("Turns a certain color into transparency. Operates on RGB colors."),
    .priv_size      = sizeof(ColorkeyOpenCLContext),
    .priv_class     = &colorkey_opencl_class,
    .init           = &ff_opencl_filter_init,
    .uninit         = &colorkey_opencl_uninit,
    .query_formats  = &ff_opencl_filter_query_formats,
    .inputs         = colorkey_opencl_inputs,
    .outputs        = colorkey_opencl_outputs,
    .flags_internal = FF_FILTER_FLAG_HWFRAME_AWARE
};
```

For the sake of time I'll skip talking about this code in detail (it's pretty easy to figure out what it all does on a need-to-know basis). We do, however, need to touch on some of the functions getting passed as callbacks. `ff_opencl_filter_query_formats`, `ff_opencl_filter_init`, `ff_opencl_filter_config_output`, and `ff_opencl_filter_config_input` are all functions that are defined for us elsewhere; from the code I've read, it looks like most other OpenCL filters all use these functions, so you're likely going to want to as well.

`colorkey_opencl_uninit` is something we need to write:

```c
static av_cold void colorkey_opencl_uninit(AVFilterContext* avctx)
{
    ColorkeyOpenCLContext* ctx = avctx->priv;
    cl_int cle;

    if (ctx->kernel_colorkey) {
        cle = clReleaseKernel(ctx->kernel_colorkey);
        if (cle != CL_SUCCESS)
            // log error
    }

    if (ctx->command_queue) {
        cle = clReleaseCommandQueue(ctx->command_queue);
        if (cle != CL_SUCCESS)
            // log error
    }

    ff_opencl_filter_uninit(avctx);
}
```

This function, as the name suggests, is used to clean up our context after the filter is finished running. This basically consists of using the appropriate functions from the `OpenCL` API on the corresponding fields of our `ColorkeyOpenClContext` that we obtain from the `priv` field of the passed `AVFilterContext`, and then calling the externally-defined `ff_opencl_filter_uninit` to handle the rest.

We also need to define `colorkey_opencl_inputs` and `colorkey_opencl_outputs`:

```c
static const AVFilterPad colorkey_opencl_inputs[] = {
    {
        .name = "default",
        .type = AVMEDIA_TYPE_VIDEO,
        .filter_frame = filter_frame,
        .config_props = &ff_opencl_filter_config_input,
    },
    { NULL }
};

static const AVFilterPad colorkey_opencl_outputs[] = {
    {
        .name = "default",
        .type = AVMEDIA_TYPE_VIDEO,
        .config_props = &ff_opencl_filter_config_output,
    },
    { NULL }
};
```

Here we're specifying arrays of input and output pads that our filter will have ("pad" is just a term used to refer to an input or output of a filter). In both cases, we define a single pad; the `colorkey` filter takes a single input and maps it to a single output. (When would you need multiple? Well, in the case of the `overlay` filter, you'll need two inputs: one for the base and one to overlay on top of it.) In both cases we also pass externally-defined functions as the `config_props` callback. The one callback that we need to write a function for is `filter_frame`, which you should recognize from our overview of the CPU filter.

Before we do that, though, let's create the OpenCL kernel that we're going to be using inside that function.

### Writing the OpenCL Kernel

Create a new file (`libavfilter/opencl/colorkey.cl`). Within it, we're going to add the following:

```c
float4 get_pixel(image2d_t src, int2 loc) {
    const sampler_t sampler = CLK_NORMALIZED_COORDS_FALSE |
                                CLK_FILTER_NEAREST;

    return read_imagef(src, sampler, loc);
}

__kernel void colorkey(
    __read_only  image2d_t src,
    __write_only image2d_t dst,
    float4 colorkey_rgba,
    float similarity
) {
    int2 loc = (int2)(get_global_id(0), get_global_id(1));
    float4 pixel = get_pixel(src, loc);
    float diff = distance(pixel.xyz, colorkey_rgba.xyz);

    pixel.s3 = (diff > similarity) ? 1.0 : 0.0;
    write_imagef(dst, loc, pixel);
}
```

The `get_pixel` function returns a pixel from `src` at `loc` (it's split off into a separate function since we'll be adding another short kernel that uses it shortly). Within the `colorkey` kernel we obtain the value for `loc` by using the `get_global_id` function that OpenCL provides. Every invocation of the kernel is going to be assigned unique IDs within a range that we'll specify when we queue the kernel to be executed; these unique IDs allow us to touch every pixel in the input image without using for loops!

Everything after obtaining the pixel is directly translated from the CPU `do_colorkey_pixel` function; we calculate the "distance" (difference) between the pixel's RGB components and the key colors' RGB components using an OpenCL built-in function and then set the pixel's alpha value based upon a comparison between that difference and the given `similarity` value.

Now for the aforementioned additional kernel:

```c
__kernel void colorkey_blend(
    __read_only  image2d_t src,
    __write_only image2d_t dst,
    float4 colorkey_rgba,
    float similarity,
    float blend
) {
    int2 loc = (int2)(get_global_id(0), get_global_id(1));
    float4 pixel = get_pixel(src, loc);
    float diff = distance(pixel.xyz, colorkey_rgba.xyz);

    pixel.s3 = clamp((diff - similarity) / blend, 0.0f, 1.0f);
    write_imagef(dst, loc, pixel);
}
```

This kernel, aptly named `colorkey_blend`, is a copy of `colorkey` with the addition of a `blend` argument that gets used in the calculation of the pixel's alpha value. Having two kernels allows us to remove an if branch: either we are blending or we aren't. This could potentially improve performance on some hardware (although I didn't notice any improvement on my own).

The OpenCL side is now complete! Let's return to CPU land and run the kernel(s).

### Running the OpenCL Kernel

The `filter_frame` callback is where we're going to be executing a kernel, and it's going to be rather long, so instead of inserting it in its entirety here I'll insert sections of it and discuss those. Note that they belong within the following function body:

```c
static int filter_frame(AVFilterLink* link, AVFrame* input_frame)
{
    AVFilterContext* avctx = link->dst;
    AVFilterLink* outlink = avctx->outputs[0];
    ColorkeyOpenCLContext* colorkey_ctx = avctx->priv;
    AVFrame* output_frame = NULL;
    int err;
    cl_int cle;
    size_t global_work[2];
    cl_mem src, dst;
    
fail:
    clFinish(colorkey_ctx->command_queue);
    av_frame_free(&input_frame);
    av_frame_free(&output_frame);
    return err;
}
```

Here we have:

* Our filter instances' `AVFilterContext` which we obtain a pointer to via `link`
* A link to the filter we are outputting to
* The specific `ColorKeyOpenCLContext` we wrote above that contains our state, obtained from the generic context
* Various variables that will be initialized later on and used throughout the function
* A `fail` label that is jumped to whenever we encounter an error and need to exit the function

Starting off, we need to do some validation and intialization:

```c
// excerpt from `filter_frame`

if (!input_frame->hw_frames_ctx)
    return AVERROR(EINVAL);

if (!colorkey_ctx->initialized) {
    AVHWFramesContext* input_frames_ctx =
        (AVHWFramesContext*)input_frame->hw_frames_ctx->data;
    int fmt = input_frames_ctx->sw_format;

    // Make sure the input is a format we support
    if (fmt != AV_PIX_FMT_ARGB &&
        fmt != AV_PIX_FMT_RGBA &&
        fmt != AV_PIX_FMT_ABGR &&
        fmt != AV_PIX_FMT_BGRA
    ) {
        av_log(avctx, AV_LOG_ERROR, "unsupported (non-RGB) format in colorkey_opencl.\n");
        err = AVERROR(ENOSYS);
        goto fail;
    }

    err = colorkey_opencl_init(avctx);
    if (err < 0)
        goto fail;
}
```

Let's break this down. The first if statement is checking to make sure that the `hw_frames_ctx` we'll need to be accessing is non-null. The second one contains code to be run if the `OpenCLFilterContext` within our filter's context structure hasn't been initialized (translation: this is the first time `filter_frame` has been called for this instance of the filter). Here we will, of course, run initialization code for the OpenCL stuff in our context, but it's also when we will perform a critical check for our particular filter. Background information: FFmpeg does not yet have code written (at the time of this writing) to negotiate formats when a hardware frame is involved. This means that while the CPU filter is simply able to provide a `query_formats` callback that tells FFmpeg's filter negotiation code what formats it supports and have that taken care of, OpenCL filters are stuck manually checking that that the input frame they've been given is in a format that they support and erroring if it is not. In our case, our filter is only going to support RGB input (just like the CPU filter it's ported from), so we manually check that that's what we're given inside of another if statement.

After making that check, we perform a call to `colorkey_opencl_init`:

```c
static int colorkey_opencl_init(AVFilterContext* avctx)
{
    ColorkeyOpenCLContext *ctx = avctx->priv;
    cl_int cle;
    int err;

    err = ff_opencl_filter_load_program(avctx, &ff_opencl_source_colorkey, 1);
    if (err < 0)
        goto fail;

    ctx->command_queue = clCreateCommandQueue(
        ctx->ocf.hwctx->context,
        ctx->ocf.hwctx->device_id,
        0, &cle
    );

    CL_FAIL_ON_ERROR(AVERROR(EIO), "Failed to create OpenCL command queue %d.\n", cle);

    if (ctx->blend > 0.0001) {
        ctx->kernel_colorkey = clCreateKernel(ctx->ocf.program, "colorkey_blend", &cle);
        CL_FAIL_ON_ERROR(AVERROR(EIO), "Failed to create colorkey_blend kernel: %d.\n", cle);
    } else {
        ctx->kernel_colorkey = clCreateKernel(ctx->ocf.program, "colorkey", &cle);
        CL_FAIL_ON_ERROR(AVERROR(EIO), "Failed to create colorkey kernel: %d.\n", cle);
    }

    for (int i = 0; i < 4; ++i) {
        ctx->colorkey_rgba_float.s[i] = (float)ctx->colorkey_rgba[i] / 255.0;
    }

    ctx->initialized = 1;
    return 0;

fail:
    if (ctx->command_queue)
        clReleaseCommandQueue(ctx->command_queue);
    if (ctx->kernel_colorkey)
        clReleaseKernel(ctx->kernel_colorkey);
    return err;
}
```

This function loads the OpenCL program that we wrote (we'll talk about where `ff_opencl_source_colorkey` is defined later), creates a command queue, sets up the appropriate kernel based on our instances' `blend` value, and initializes the normalized float version of the key color.

Next we have some initialization that occurs for every call to `filter_frame`:

```c
// excerpt from `filter_frame`

src = (cl_mem)input_frame->data[0];
output_frame = ff_get_video_buffer(outlink, outlink->w, outlink->h);
if (!output_frame) {
    err = AVERROR(ENOMEM);
    goto fail;
}
dst = (cl_mem)output_frame->data[0];
```

First, we set the `src` variable to the image data that we were given as input, cast as `cl_mem` for usage with OpenCL. Since we know we will be working with RGB input we can simply grab the first plane from the `data` array (RGB data is always stored in a single plane). We then set `output_frame` to a buffer with the appropriate dimensions for the filter we are outputting to and make sure that the allocation of the buffer was successful. Finally, we set the `dst` variable to the first plane of the data of our output buffer, just like what we did for the input.

There's still one more thing we need to do before we can run our OpenCL kernel: we need to pass it its arguments.

```c
// excerpt from `filter_frame`

CL_SET_KERNEL_ARG(colorkey_ctx->kernel_colorkey, 0, cl_mem, &src);
CL_SET_KERNEL_ARG(colorkey_ctx->kernel_colorkey, 1, cl_mem, &dst);
CL_SET_KERNEL_ARG(colorkey_ctx->kernel_colorkey, 2, cl_float4, &colorkey_ctx->colorkey_rgba_float);
CL_SET_KERNEL_ARG(colorkey_ctx->kernel_colorkey, 3, float, &colorkey_ctx->similarity);
if (colorkey_ctx->blend > 0.0001) {
    CL_SET_KERNEL_ARG(colorkey_ctx->kernel_colorkey, 4, float, &colorkey_ctx->blend);
}
```

FFmpeg sticks to an older version of the OpenCL API for compatibility, which unfortunately means we're stuck setting kernel arguments based on an index number rather than via the name of the argument (which is more error-prone). FFmpeg has a helper macro already written (`CL_SET_KERNEL_ARG`) that makes setting arguments quick and easy for us. Note that we set the `blend` argument based on the same condition we wrote to determine which kernel to use; if we're not doing blending then we're not even able to pass that argument as it won't be a part of our kernel.

With all of that out of the way, it's finally time to run the kernel!

```c
err = ff_opencl_filter_work_size_from_image(avctx, global_work, input_frame, 0, 0);
if (err < 0)
    goto fail;

cle = clEnqueueNDRangeKernel(
    colorkey_ctx->command_queue,
    colorkey_ctx->kernel_colorkey,
    2,
    NULL,
    global_work,
    NULL,
    0,
    NULL,
    NULL
);

CL_FAIL_ON_ERROR(AVERROR(EIO), "Failed to enqueue colorkey kernel: %d.\n", cle);

// Run queued kernel
cle = clFinish(colorkey_ctx->command_queue);
CL_FAIL_ON_ERROR(AVERROR(EIO), "Failed to finish command queue: %d.\n", cle);
```

We enqueue the kernel to be executed using the `clEnqueueNDRangeKernel` function (which you can read in depth about [here](https://www.khronos.org/registry/OpenCL/sdk/1.2/docs/man/xhtml/)). Among other things, we pass it our command queue and kernel along with a `global_work` variable. Before making this call, we've made a call to `ff_opencl_filter_work_size_from_image` to initialize `global_work`; it's a helper function that determines the work size based on the dimensions of our `input_frame`. This `global_work` array specifies the range that OpenCL will choose IDs from to hand to kernel instances.

After enqueuing the kernel, it's a simple matter of calling `clFinish` on the command queue to run the kernel to completion across the `global_work` range (plus the appropriate error handling).

That brings us to the conclusion of `filter_frame`:

```c
err = av_frame_copy_props(output_frame, input_frame);
if (err < 0)
    goto fail;

av_frame_free(&input_frame);

return ff_filter_frame(outlink, output_frame);
```

At the end of the function, we copy the metadata of our `input_frame` to the `output_frame` using `av_frame_copy_props`, free `input_frame`, and return the result of `ff_filter_frame`, a function that forwards `output_frame` to the next filter.

That's all for the `colorkey_opencl` filter implementation!

### Hooking the Filter Into the Rest of the Framework

In order to compile FFmpeg with our filter enabled, we'll need to add some lines to a few different files. In `libavfilter/Makefile`:

```c
OBJS-$(CONFIG_COLORKEY_OPENCL_FILTER) += vf_colorkey_opencl.o opencl.o \
                                         opencl/colorkey.o
```

This line adds the OpenCl code that we wrote into the build system. Next, in `libavfilter/allfilters.c`:

```c
extern AVFilter ff_vf_colorkey_opencl;
```

The `allfilters` file, as the name would suggest, simply lists all of the filters included in FFmpeg, and we add ours there accordingly. Finally, in `libavfilter/opencl_source.h`:

```c
extern const char *ff_opencl_source_colorkey;
```

This file collects all of the compiled OpenCL sources. The `ff_opencl_source_colorkey` symbol is the same one that we'll reference later when we call `ff_opencl_filter_load_program` within `colorkey_opencl_init`.

### Testing the Filter

We can now compile FFmpeg again, this time with our filter being built as well!

```
make -j 8
```

Let's try the filter:

```bash
time ./ffmpeg -i ../trimmed_video.mp4 -i img.jpg -init_hw_device opencl=gpu -filter_hw_device gpu -filter_complex "[0:v]format=rgba, hwupload, colorkey_opencl=yellow:0.4:0.2, hwdownload, format=rgba[over];[1:v][over]overlay" ../trimmed_video_colorkey.mp4
```

The times for that invocation:

```
real    0m38.056s
user    3m1.398s
sys     0m2.892s
```

For comparison, let's test the CPU version of the filter:

```bash
time ./ffmpeg -i ../trimmed_video.mp4 -i img.jpg -filter_complex "[0:v]colorkey=yellow:0.4:0.2[ckout];[1:v][ckout]overlay" ../trimmed_video_colorkey_cpu.mp4
```

```
real    0m43.661s
user    3m34.862s
sys     0m1.796s
```

Similar to the `avgblur` comparison that we made all the way at the beginning of this blog post, the OpenCL filter is decreasing overall runtime by over 10% and decreasing CPU time despite the overhead of uploading and downloading frames to and from the GPU.

### Side Note: Remember That Bugs Can Occur Outside of Your Code

During the process of writing this filter I actually ran into a bug in FFmpeg's OpenCL utility code. The `opencl_get_plane_format` function responsible for determining the image format that should be used when allocating an OpenCL image for the data on a plane was incorrectly setting the channel order for all RGB formats to `CL_RGBA`, causing the use of any other RGB format to result in incorrect filter output (and also causing certain RGB formats to be incorrectly reported as supported by my hardware). I submitted [a patch](https://patchwork.ffmpeg.org/patch/12635/) to fix this bug while wrapping up work on the filter.

I bring this up to remind you, the reader, to always remember that bugs *can* occur outside of your code, too! Investigate that possibility before you spend lots of time trying to figure out what you're doing wrong like I did :).

## Conclusion

Wow, that ended up being a lot of words. We've gone from (in my case) having never worked with FFmpeg's codebase to having ourselves a functioning port of a CPU filter that gets run on the GPU via the OpenCL API.

Hopefully you found this post informative in some way (or at least interesting!). I have no idea if I'm going to be accepted into the Google Summer of Code program yet, but if I am, I certainly plan on writing more blog posts throughout the summer. Feel free to follow me [on Twitter](https://twitter.com/_cldfire) if you'd like to know when those go live.
